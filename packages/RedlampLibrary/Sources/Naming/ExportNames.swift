import Foundation
import RedlampDocument
import RedlampEngineAPI

/// The files a batch of exports writes (EDT-16), one photo or many. Each photo is named by the settings'
/// template (LIB-25), its sequences numbering the photos in the batch's order and `{total}` counting them,
/// and goes in the folder the settings choose. No two photos get one name: those after the first are
/// numbered in the order they were taken, a raw's export and its JPEG's included. Then the files already
/// there: a photo is never replaced, whatever the rule says, and gets the first free number instead; an
/// earlier export is replaced, numbered, skipped or asked about, as the settings' rule for existing files
/// says (`ExportDestination.isPhoto` tells the two apart).
public struct ExportNames: Sendable {
    /// A photo to export, and what its name is made from.
    public struct Photo: Sendable, Hashable {
        public var url: URL
        public var fields: NamingFields

        public init(url: URL, fields: NamingFields) {
            self.url = url
            self.fields = fields
        }

        /// What `url` says alone: the photo's name and folder.
        public init(url: URL) {
            self.init(url: url, fields: NamingFields(
                name: url.lastPathComponent, folder: url.deletingLastPathComponent().path,
            ))
        }
    }

    /// Where one photo's export goes.
    public struct Target: Sendable, Hashable {
        public var photo: URL
        public var url: URL
        public var existing: Existing
    }

    /// What's at a target's file before the export.
    public enum Existing: Sendable, Hashable {
        /// Nothing.
        case none
        /// An earlier export, which the export replaces.
        case replaced
        /// An earlier export, left as it is: the photo isn't exported.
        case skipped
        /// An earlier export, which the person is asked about once for the batch (the rule is Ask).
        case asked
    }

    /// One for each photo, in the batch's order.
    public let targets: [Target]
    /// The named counters as they'll be once the batch is exported.
    public let counters: NamingCounters

    /// The photos to export: those not skipped.
    public var written: [Target] {
        targets.filter { $0.existing != .skipped }
    }

    /// How many targets are earlier exports to ask about.
    public var asked: Int {
        targets.count { $0.existing == .asked }
    }

    /// The names for `photos` exported with `settings`, `files` reading the tags of files already there.
    /// Throws when the template doesn't read.
    public init(
        _ photos: [Photo], settings: ExportSettings, context: NamingContext = NamingContext(),
        counters: NamingCounters = NamingCounters(), reading files: any FileInspecting,
        fileManager: FileManager = .default,
    ) throws(NamingTemplateError) {
        let template = try NamingTemplate(parsing: settings.naming.template)
        var context = context
        context.texts = settings.naming.texts
        let destination = settings.destinationFolder?.path
        let job = NamingJob(photos.map { NamingPhoto($0.fields, destination: destination) }, pairing: false)
        let batch = job.names(
            template, options: NamingOptions(sequenceStart: settings.naming.sequenceStart), context: context,
            counters: counters,
        )
        var named = zip(photos, batch.results).map { photo, result in
            ExportDestination.named(result.base, for: photo.url, settings: settings)
        }
        var claimed = Set(named.map(Self.key))
        var existing = [Existing](repeating: .none, count: named.count)
        for index in named.indices where fileManager.fileExists(atPath: named[index].path) {
            let url = named[index]
            let policy = ExportDestination.isPhoto(url, source: photos[index].url, reading: files)
                ? .addNumber : settings.existingFiles
            switch policy {
            case .addNumber:
                let free = ExportDestination.firstFree(url, taken: { claimed.contains(Self.key($0)) })
                claimed.insert(Self.key(free))
                named[index] = free
            case .overwrite: existing[index] = .replaced
            case .skip: existing[index] = .skipped
            case .ask: existing[index] = .asked
            }
        }
        targets = photos.indices.map { Target(photo: photos[$0].url, url: named[$0], existing: existing[$0]) }
        self.counters = batch.counters
    }

    /// The targets with the earlier exports that were to be asked about replaced, numbered or skipped, as
    /// `answer` says.
    public func answering(_ answer: ExistingFilePolicy, fileManager: FileManager = .default) -> [Target] {
        var claimed = Set(targets.map { Self.key($0.url) })
        return targets.map { target in
            guard target.existing == .asked else { return target }
            var answered = target
            switch answer {
            case .overwrite, .ask: answered.existing = .replaced
            case .skip: answered.existing = .skipped
            case .addNumber:
                answered.url = ExportDestination.firstFree(
                    target.url, taken: { claimed.contains(Self.key($0)) }, fileManager: fileManager,
                )
                answered.existing = .none
                claimed.insert(Self.key(answered.url))
            }
            return answered
        }
    }

    /// A file's path as APFS compares names: composed, ignoring case.
    private static func key(_ url: URL) -> String {
        url.path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
