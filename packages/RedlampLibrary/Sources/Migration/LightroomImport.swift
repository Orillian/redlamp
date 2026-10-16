import Foundation
import RedlampDocument
import RedlampEngineAPI
import Synchronization

/// An import from a Lightroom Classic catalog, as the library keeps it to take back (LIB-29): its batches
/// in the keyword and metadata journals, in the order they ran.
public struct LightroomImportRecord: Sendable, Hashable, Codable, Identifiable {
    public struct Batch: Sendable, Hashable, Codable {
        public enum Journal: String, Sendable, Hashable, Codable {
            case keywords, metadata
        }

        public var journal: Journal
        public var id: UUID
    }

    /// A photo whose edit it made in the editor, where the photo was open: its sidecar's `recipe` and `snapshots`
    /// before and after, as the sidecar writes them.
    public struct EditorChange: Sendable, Hashable, Codable {
        public var photo: Int64
        public var path: String
        public var before: [String: JSONValue]
        public var after: [String: JSONValue]
    }

    public var id: UUID
    /// The catalog's path.
    public var catalog: String
    public var date: Date
    /// Photos whose fields, keywords or edits it changed.
    public var photos = 0
    public var batches: [Batch] = []
    /// Optional, as records written before edits were imported lack it.
    public var inEditor: [EditorChange]?
    /// Stopped before every part ran.
    public var stopped = false
    public var undone = false
}

/// The editor, to an import (EDT-23): the photo open in it takes its edit there, as a step of its history, never
/// by its sidecar being written behind it, as Settings Sync does.
public struct LightroomEditor: Sendable {
    public enum Outcome: Sendable, Hashable {
        /// Made as a step of the photo's history: the edit and snapshots it had, and the edit it has now.
        case changed(EditRecipe, [Snapshot], EditRecipe)
        /// Left as it is: edited since, or read-only.
        case left
        /// It isn't open in the editor (any more).
        case notOpen
    }

    /// The path of the photo open in the editor, or opening there.
    public var open: @Sendable () async -> String?
    /// Gives the photo open at `path` the edit `recipe` while its edit is `over` (nil: while it's unedited), with
    /// `adding` after its snapshots and those with IDs in `removing` taken off.
    public var change: @Sendable (
        _ path: String, _ recipe: EditRecipe, _ over: EditRecipe?, _ adding: [Snapshot], _ removing: Set<UUID>,
    ) async -> Outcome

    public init(
        open: @escaping @Sendable () async -> String?,
        change: @escaping @Sendable (String, EditRecipe, EditRecipe?, [Snapshot], Set<UUID>) async -> Outcome,
    ) {
        self.open = open
        self.change = change
    }
}

/// Why an import couldn't be made or taken back.
public enum LightroomImportError: Error, Sendable, Hashable, CustomStringConvertible {
    case nothingToUndo
    /// Some of an import's batches can't be taken back: the journals no longer have them as they ran.
    case partlyUndone([String])

    public var description: String {
        switch self {
        case .nothingToUndo: "there's no import from Lightroom Classic to undo"
        case let .partlyUndone(titles): "these weren't taken back: \(titles.joined(separator: "; "))"
        }
    }
}

/// Runs a Lightroom Classic catalog's import into the library (LIB-29) as the library's batches, so the
/// sidecars, the index, the open lists, Undo and the recovery after a forced quit work as for every change.
///
/// - **In parts** of `partSize` photos, each a metadata batch: each photo's fields, keywords, collections and
///   edit with its snapshots (EDT-23), so its sidecar is written once, and with the first part the collection
///   definitions (sets, smart collections and collections without photos). The keyword definitions (synonyms,
///   export options and keywords no photo has) go first, as a keyword batch of no photos. `stop` is asked
///   between parts, so a stopped import leaves whole batches, which Undo takes back.
/// - **Edits** go to photos whose sidecars hold no edit when they're written: a photo edited in Redlamp keeps
///   its edit. The photo open in the editor takes its edit there (`LightroomEditor`).
/// - **Undo** takes back every batch of the import, newest first, each keeping what changed since, as a
///   batch's Undo does.
/// - **The record** of imports (`Lightroom Imports.json` in the library's folder) names each import's batches,
///   written as each finishes, so an import a quit cut short can still be taken back.
public final class LightroomImport: Sendable {
    public let index: LibraryIndex
    public let paths: LibraryPaths
    public let live: LibraryLive?
    /// Photos a part takes.
    public let partSize: Int
    public static let standardPartSize = 10000
    /// Imports the record keeps; older ones go.
    static let kept = 20
    /// Runs each batch: at once by default; the app runs each in the library's turn for changes, so the
    /// syncs of other apps' metadata and the changes asked for meanwhile go between them.
    private let turn: (@Sendable (@escaping @Sendable () async -> Void) async -> Void)?
    /// Hears of the photos each batch changed, as the app's other apps' metadata follows them.
    private let changed: (@Sendable ([Int64]) -> Void)?
    private let editor: LightroomEditor?
    private static let recordLock = Mutex(())

    public init(
        index: LibraryIndex, paths: LibraryPaths? = nil, live: LibraryLive? = nil,
        partSize: Int = LightroomImport.standardPartSize,
        turn: (@Sendable (@escaping @Sendable () async -> Void) async -> Void)? = nil,
        changed: (@Sendable ([Int64]) -> Void)? = nil, editor: LightroomEditor? = nil,
    ) {
        self.index = index
        self.paths = paths ?? LibraryPaths(root: index.url.deletingLastPathComponent())
        self.live = live
        self.partSize = max(partSize, 1)
        self.turn = turn
        self.changed = changed
        self.editor = editor
    }

    private var keywords: LibraryKeywords {
        LibraryKeywords(index: index, paths: paths, live: live)
    }

    private var metadata: LibraryMetadata {
        LibraryMetadata(index: index, paths: paths, live: live)
    }

    /// How far an import or its Undo has got: photos done of the photos it takes, and its parts.
    public struct Progress: Sendable, Hashable {
        public var done: Int
        public var total: Int
        public var part: Int
        public var parts: Int

        public init(done: Int, total: Int, part: Int, parts: Int) {
            self.done = done
            self.total = total
            self.part = part
            self.parts = parts
        }
    }

    /// What an import did.
    public struct Outcome: Sendable, Hashable {
        public var record: LightroomImportRecord
        /// Sidecars written.
        public var written = 0
        /// Photos whose sidecars this build can't write, left as they were, by path, and why.
        public var skipped: [String: String] = [:]
    }

    // MARK: - Importing

    /// Runs `plan`: the keyword definitions, then each part's metadata batch, `progress` hearing of the photos
    /// done and `stop` asked before each part after the first. A batch that fails is rolled back and the error
    /// thrown; the parts before it stay, in the record, for Undo.
    @discardableResult
    public func run(
        _ plan: LightroomPlan, progress: (@Sendable (Progress) -> Void)? = nil, stop: (@Sendable () -> Bool)? = nil,
    ) async throws -> Outcome {
        try await settle()
        var outcome = Outcome(record: LightroomImportRecord(id: UUID(), catalog: plan.report.catalog, date: Date()))
        let photos = plan.photos
        let parts = max(1, (photos.count + partSize - 1) / partSize)
        var changedPhotos = Set<Int64>()
        try save(outcome.record)
        let whole = Self.title(plan.name, photos: photos.count, part: 0, of: 1, count: photos.count)
        let definitions = try await keywordPlan(plan.keywords, title: "Import the keywords of \(whole)")
        if !definitions.isEmpty {
            let ran = try await inTurn { [keywords] in try await keywords.run(definitions) }
            outcome.record.batches.append(.init(journal: .keywords, id: ran.batch))
            try save(outcome.record)
        }
        for part in 0 ..< parts {
            if part > 0, stop?() == true {
                outcome.record.stopped = true
                break
            }
            let slice = Array(photos[min(part * partSize, photos.count) ..< min((part + 1) * partSize, photos.count)])
            let start = part * partSize
            let title = Self.title(plan.name, photos: photos.count, part: part, of: parts, count: slice.count)
            let report: @Sendable (Double) -> Void = { fraction in
                progress?(Progress(
                    done: start + Int(Double(slice.count) * fraction), total: photos.count, part: part, parts: parts,
                ))
            }
            let open = await editor?.open()
            let (metadataPlan, inEditor) = try await metadataPlan(
                slice, edits: plan.edits, leaving: open, definitions: part == 0 ? plan.collections : [:],
                title: "Import \(title)",
            )
            if !metadataPlan.isEmpty {
                try await run(metadataPlan, into: &outcome, changed: &changedPhotos, report: report)
            }
            if let inEditor {
                try await change(inEditor, into: &outcome, changed: &changedPhotos, title: "Import \(title)")
            }
            outcome.record.photos = changedPhotos.count
            try save(outcome.record)
            report(1)
        }
        try save(outcome.record)
        return outcome
    }

    /// Runs one of the import's metadata batches, which the record keeps.
    private func run(
        _ plan: MetadataPlan, into outcome: inout Outcome, changed changedPhotos: inout Set<Int64>,
        report: (@Sendable (Double) -> Void)? = nil,
    ) async throws {
        let ran = try await inTurn { [metadata] in
            try await metadata.run(plan) { done, total in report?(Double(done) / Double(max(total, 1))) }
        }
        outcome.record.batches.append(.init(journal: .metadata, id: ran.batch))
        outcome.written += ran.written
        outcome.skipped.merge(ran.reasons) { first, _ in first }
        let ids = plan.photos.map(\.id)
        changedPhotos.formUnion(ids)
        changed?(ids)
        if plan.batch.definitions != nil {
            live?.namesChanged()
        }
        try save(outcome.record)
    }

    /// Makes the edit of the photo open in the editor there; one no longer open has it written as a batch of its
    /// own.
    private func change(
        _ photo: (id: Int64, path: String, edit: LightroomEdit), into outcome: inout Outcome,
        changed changedPhotos: inout Set<Int64>, title: String,
    ) async throws {
        let made = photo.edit.made()
        let recipe = JSONValue(sidecar: made.recipe)?.decoded(as: EditRecipe.self) ?? made.recipe
        let snapshots = JSONValue(sidecar: made.snapshots)?.decoded(as: [Snapshot].self) ?? made.snapshots
        switch await editor?.change(photo.path, recipe, nil, snapshots, []) ?? .notOpen {
        case let .changed(previous, had, now):
            let change = LightroomImportRecord.EditorChange(
                photo: photo.id, path: photo.path,
                before: [
                    "recipe": JSONValue(sidecar: previous) ?? .null,
                    "snapshots": JSONValue(sidecar: had) ?? .null,
                ],
                after: [
                    "recipe": JSONValue(sidecar: now) ?? .null,
                    "snapshots": JSONValue(sidecar: had + snapshots) ?? .null,
                ],
            )
            outcome.record.inEditor = (outcome.record.inEditor ?? []) + [change]
            changedPhotos.insert(photo.id)
        case .left:
            break
        case .notOpen:
            var batch = MetadataBatch(kind: .metadata, title: title)
            batch.photos = try await metadata.photos(
                [photo.id], edits: [photo.id: [:]], edit: [:], keepingUnchanged: true,
            )
            for place in batch.photos.indices {
                batch.photos[place].develop = Self.develop(recipe, snapshots)
            }
            guard !batch.photos.isEmpty else { return }
            try await run(MetadataPlan(batch: batch), into: &outcome, changed: &changedPhotos)
        }
    }

    /// `1,200 photos from “Lightroom Catalog”`, and which part when there are several.
    static func title(_ name: String, photos: Int, part: Int, of parts: Int, count: Int) -> String {
        let whole = "\(LibraryMetadata.count(parts == 1 ? count : photos)) from “\(name)”"
        guard parts > 1 else { return whole }
        return "\(whole), part \(part + 1) of \(parts)"
    }

    /// Finishes the keyword and metadata batches a forced quit left unfinished, which would stop a new one.
    private func settle() async throws {
        if try await !keywords.unfinishedEntries().isEmpty {
            try await keywords.recover()
        }
        if try await !metadata.unfinishedEntries().isEmpty {
            try await metadata.recover()
        }
    }

    /// The keyword batch of the keyword definitions, with no photos: Lightroom's options for each keyword join
    /// those the definitions keep.
    func keywordPlan(_ definitions: [KeywordPath: KeywordOptions], title: String) async throws -> KeywordPlan {
        var batch = KeywordBatch(kind: .define, title: title)
        if !definitions.isEmpty {
            let old = try await keywords.definitions()
            var new = old
            for (path, options) in definitions {
                new.keywords[path] = Self.merged(options, into: old.keywords[path])
            }
            let change = DefinitionsChange(from: old, to: new)
            batch.definitions = change.isEmpty ? nil : change
        }
        return KeywordPlan(batch: batch)
    }

    /// Lightroom's options for a keyword the definitions may keep already: its synonyms join those kept, and
    /// its export options and whether it's a person replace theirs; a category or a private keyword stays one.
    static func merged(_ options: KeywordOptions, into kept: KeywordOptions?) -> KeywordOptions {
        guard var merged = kept else { return options }
        merged.synonyms = KeywordOptions.tidied(merged.synonyms + options.synonyms)
        merged.includeOnExport = options.includeOnExport
        merged.exportContainingKeywords = options.exportContainingKeywords
        merged.exportSynonyms = options.exportSynonyms
        merged.isPerson = options.isPerson
        return merged
    }

    /// The metadata batch of `part`: each photo's fields, the keywords Lightroom gives it that it lacks (after
    /// those it has), its collections, and its edit with its snapshots, made now; and the collections'
    /// definitions. The photo at `open`, open in the editor, is left without its edit, which comes back to be
    /// made there.
    func metadataPlan(
        _ part: [(id: Int64, values: LightroomValues)], edits developed: [Int64: LightroomEdit], leaving open: String?,
        definitions: [CollectionPath: CollectionOptions], title: String,
    ) async throws -> (plan: MetadataPlan, inEditor: (id: Int64, path: String, edit: LightroomEdit)?) {
        let keyworded = part.filter { !$0.values.keywords.isEmpty }.map(\.id)
        let shown = try await index.read { try $0.keywordPaths(ofPhotos: keyworded) }
        var edits: [Int64: [String: FieldEdit]] = [:]
        var withEdits = Set<Int64>()
        for (id, values) in part {
            var edit = values.edits
            let current = shown[id] ?? []
            let adding = values.keywords.filter { !current.contains($0) }
            if !adding.isEmpty {
                edit["keywords"] = .add(adding.map(\.text))
            }
            if developed[id] != nil {
                withEdits.insert(id)
            }
            if !edit.isEmpty || developed[id] != nil {
                edits[id] = edit
            }
        }
        var batch = MetadataBatch(kind: .metadata, title: title)
        batch.photos = try await metadata.photos(
            Array(edits.keys), edits: edits, edit: [:], keepingUnchanged: false, keeping: withEdits,
        )
        let inEditor = batch.photos.first { $0.path == open }.flatMap { photo in
            developed[photo.id].map { (id: photo.id, path: photo.path, edit: $0) }
        }
        let made = Self.develop(batch.photos.map { $0.path == open ? nil : developed[$0.id] }, date: Date())
        for place in batch.photos.indices {
            batch.photos[place].develop = made[place]
        }
        if !definitions.isEmpty {
            let old = try await metadata.collections.definitions()
            var new = old
            for (path, options) in definitions where old.collections[path] == nil
                || options.kind == .smart && old.collections[path]?.kind == .smart {
                new.collections[path] = options
            }
            let change = CollectionsChange(from: old, to: new)
            batch.definitions = change.isEmpty ? nil : change
        }
        return (MetadataPlan(batch: batch), inEditor)
    }

    /// Each of `edits` with its snapshots as a batch carries them, made on every core, `date` the snapshots'.
    static func develop(_ edits: [LightroomEdit?], date: Date) -> [MetadataBatch.Develop?] {
        let made = Mutex([MetadataBatch.Develop?](repeating: nil, count: edits.count))
        let chunk = 64
        DispatchQueue.concurrentPerform(iterations: (edits.count + chunk - 1) / chunk) { number in
            let range = number * chunk ..< min((number + 1) * chunk, edits.count)
            let developed = range.map { place in
                edits[place].flatMap { edit in
                    let (recipe, snapshots) = edit.made(date: date)
                    return develop(recipe, snapshots)
                }
            }
            made.withLock { $0.replaceSubrange(range, with: developed) }
        }
        return made.withLock { $0 }
    }

    /// An edit and its snapshots as a batch carries them.
    static func develop(_ recipe: EditRecipe, _ snapshots: [Snapshot]) -> MetadataBatch.Develop? {
        guard let recipe = JSONValue(sidecar: recipe) else { return nil }
        return MetadataBatch.Develop(recipe: recipe, snapshots: snapshots.compactMap { JSONValue(sidecar: $0) })
    }

    /// `body` in the turn the app gives batches, or at once.
    private func inTurn<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        guard let turn else { return try await body() }
        let result = Mutex<Result<T, any Error>?>(nil)
        await turn {
            let outcome: Result<T, any Error>
            do {
                outcome = try await .success(body())
            } catch {
                outcome = .failure(error)
            }
            result.withLock { $0 = outcome }
        }
        guard let outcome = result.withLock({ $0 }) else { throw CancellationError() }
        return try outcome.get()
    }

    // MARK: - Undo

    /// The newest import not taken back.
    public func lastImport() throws -> LightroomImportRecord? {
        try records().last { !$0.undone && !($0.batches.isEmpty && ($0.inEditor ?? []).isEmpty) }
    }

    /// Takes back import `id` (the newest not taken back when nil): each of its batches, newest first, each
    /// keeping what changed since. Throws `partlyUndone` naming the batches the journals no longer have as
    /// they ran, once the others are taken back.
    @discardableResult
    public func undo(_ id: UUID? = nil, progress: (@Sendable (Progress) -> Void)? = nil) async throws
        -> LightroomImportRecord {
        try await settle()
        guard var record = try id.map({ id in try records().first { $0.id == id && !$0.undone } }) ?? lastImport()
        else { throw LightroomImportError.nothingToUndo }
        let keywordEntries = try await keywords.entries()
        let metadataEntries = try await metadata.entries()
        var failed: [String] = []
        for (number, batch) in record.batches.reversed().enumerated() {
            progress?(Progress(done: number, total: record.batches.count, part: number, parts: record.batches.count))
            switch batch.journal {
            case .keywords:
                guard let entry = keywordEntries.first(where: { $0.id == batch.id }) else {
                    failed.append("a keyword change no longer in the journal")
                    continue
                }
                guard entry.state == .finished else { continue }
                _ = try await inTurn { [keywords] in try await keywords.undo(batch.id) }
            case .metadata:
                guard let entry = metadataEntries.first(where: { $0.id == batch.id }) else {
                    failed.append("a metadata change no longer in the journal")
                    continue
                }
                guard entry.state == .finished else { continue }
                _ = try await inTurn { [metadata] in try await metadata.undo(batch.id) }
                live?.namesChanged()
            }
        }
        for change in (record.inEditor ?? []).reversed() {
            try await takeBack(change)
        }
        record.undone = true
        try save(record)
        if !failed.isEmpty {
            throw LightroomImportError.partlyUndone(failed)
        }
        return record
    }

    /// Takes back an edit the import made in the editor, while the photo's edit is as the import left it: there,
    /// if the photo is open still, otherwise in its sidecar, as a batch of its own.
    private func takeBack(_ change: LightroomImportRecord.EditorChange) async throws {
        if let editor, let before = change.before["recipe"]?.decoded(as: EditRecipe.self),
           let after = change.after["recipe"]?.decoded(as: EditRecipe.self) {
            let had = Set((change.before["snapshots"]?.decoded(as: [Snapshot].self) ?? []).map(\.id))
            let added = (change.after["snapshots"]?.decoded(as: [Snapshot].self) ?? []).map(\.id)
            switch await editor.change(change.path, before, after, [], Set(added).subtracting(had)) {
            case .changed, .left: return
            case .notOpen: break
            }
        }
        var batch = MetadataBatch(kind: .undo, title: "Undo the edit imported from Lightroom Classic")
        batch.photos = [MetadataBatch.Photo(
            id: change.photo, path: change.path, index: [:],
            undo: MetadataBatch.Undo(
                sidecarBefore: change.before, sidecarAfter: change.after, indexBefore: [:], indexAfter: [:],
            ),
        )]
        let plan = MetadataPlan(batch: batch)
        _ = try await inTurn { [metadata] in try await metadata.run(plan) }
    }

    // MARK: - The record

    /// `Lightroom Imports.json` in the library's folder.
    public var recordURL: URL {
        paths.root.appending(path: "Lightroom Imports.json")
    }

    /// The imports the record keeps, oldest first.
    public func records() throws -> [LightroomImportRecord] {
        try Self.recordLock.withLock { _ in try load() }
    }

    private func load() throws -> [LightroomImportRecord] {
        let data: Data
        do {
            data = try Data(contentsOf: recordURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LightroomImportRecord].self, from: data)
    }

    /// Keeps `record` in place of the one with its ID, or newest.
    private func save(_ record: LightroomImportRecord) throws {
        try Self.recordLock.withLock { _ in
            var records = (try? load()) ?? []
            if let place = records.firstIndex(where: { $0.id == record.id }) {
                records[place] = record
            } else {
                records.append(record)
            }
            records = Array(records.suffix(Self.kept))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            try encoder.encode(records).write(to: recordURL, options: .atomic)
        }
    }
}
