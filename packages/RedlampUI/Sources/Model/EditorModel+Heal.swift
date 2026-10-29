import AppKit
import Foundation
import ImageIO
import RedlampDocument
import RedlampEngineAPI

/// The Healing tool's settings for the next spot, in the sliders' units.
public struct SpotSettings: Hashable, Sendable {
    public var size: Double = ParameterID.spotSize.spec.defaultValue
    public var feather: Double = ParameterID.spotFeather.spec.defaultValue
    public var opacity: Double = ParameterID.spotOpacity.spec.defaultValue
    public var visualize: Double = ParameterID.spotVisualize.spec.defaultValue

    public init() {}

    public subscript(parameter: ParameterID) -> Double {
        get {
            switch parameter {
            case .spotSize: size
            case .spotFeather: feather
            case .spotOpacity: opacity
            case .spotVisualize: visualize
            default: parameter.spec.defaultValue
            }
        }
        set {
            let value = parameter.spec.clamp(newValue)
            switch parameter {
            case .spotSize: size = value
            case .spotFeather: feather = value
            case .spotOpacity: opacity = value
            case .spotVisualize: visualize = value
            default: break
            }
        }
    }
}

extension RetouchSpot {
    /// Size 1...100 as a radius (a fraction of the image height): from a speck of dust to a fifth
    /// of the photo, finer at the small end.
    static func radius(size: Double) -> Double {
        0.004 + 0.2 * pow(min(max(size, 1), 100) / 100, 2)
    }

    static func size(radius: Double) -> Double {
        min(max(100 * (max(radius - 0.004, 0) / 0.2).squareRoot(), 1), 100)
    }

    subscript(parameter: ParameterID) -> Double {
        switch parameter {
        case .spotSize: Self.size(radius: radius)
        case .spotFeather: feather
        case .spotOpacity: opacity
        default: parameter.spec.defaultValue
        }
    }
}

/// What a click in the Healing tool does: add a spot, or pick a person or an object to remove.
public enum SpotPick: String, CaseIterable, Sendable {
    case spot
    case person
    case object

    public var name: String {
        switch self {
        case .spot: "Spot"
        case .person: "Person"
        case .object: "Object"
        }
    }
}

/// The Healing tool: Remove, Heal and Clone spots (RM-01, RM-07, RM-08).
public extension EditorModel {
    /// How far a picked person or object's mask grows to cover its edge and contact shadow, as a
    /// fraction of the image height.
    static let regionGrowth = 0.005

    /// Removes the person or object under `point` (`spotPick`), its own mask grown a little.
    func pickRegion(at point: ImagePoint) async {
        switch spotPick {
        case .spot: return
        case .person: await pickRegion(MaskRequest(kind: .people)) { Self.mask(at: point, in: $0) }
        case .object: await pickRegion(MaskRequest(kind: .objects, prompts: [point]))
        }
    }

    /// Removes the object a box is dragged around with Click picks on Object: Segment Anything's
    /// box prompt, as an Objects mask's Rectangle selects it.
    func pickRegion(in box: ImageRect) async {
        guard spotPick == .object else { return }
        await pickRegion(MaskRequest(kind: .objects, box: box))
    }

    /// Removes the object brushed over with Click picks on Object, from points spread along the
    /// stroke, as an Objects mask's Brush selects it. A stroke that passes over the selected object
    /// pick, or comes within `reach` of it (a fraction of the image height), adds what it brushes to
    /// that pick instead, such as a handle the pick left out.
    func pickRegion(along stroke: [ImagePoint], reach: Double) async {
        guard spotPick == .object, !stroke.isEmpty, !isPickingRegion else { return }
        let points = Self.prompts(along: stroke)
        if let spot = selectedSpot, let region = spot.region, region.kind == .objects, let png = region.bitmap.png {
            let within = reach + spot.radius
            let touches = await Task.detached(priority: .userInitiated) {
                Self.touches(stroke, mask: png, within: within)
            }.value
            if touches {
                // The box a pick was asked with bounds what's found, so it grows to take the stroke in.
                await pickRegion(
                    MaskRequest(
                        kind: .objects, prompts: region.prompts + points, excluded: region.excludedPrompts ?? [],
                        box: region.box.map { Self.box($0, around: stroke) },
                    ),
                    adding: (spot.id, region),
                )
                return
            }
        }
        await pickRegion(MaskRequest(kind: .objects, prompts: points))
    }

    /// Removes what `request` finds (the mask `choose` takes of those found) as a new Remove spot,
    /// its mask grown a little; or, `adding` to an object pick that still has `region`, reshapes
    /// that pick to it.
    private func pickRegion(
        _ request: MaskRequest, adding target: (id: UUID, region: AIMask)? = nil,
        choose: ([AIMask]) -> AIMask? = { $0.first },
    ) async {
        guard let visit = currentVisit, !isPickingRegion else { return }
        let pick: SpotPick = request.kind == .people ? .person : .object
        pickMessage = nil
        if availableAIMaskKinds.isEmpty {
            await refreshAvailableMasks()
        }
        guard availableAIMaskKinds.contains(request.kind) else {
            pickMessage = "Picking \(pick.name.lowercased())s isn't available for this photo."
            return
        }
        if let model = await engine.modelNeeded(for: request.kind) {
            pickMessage = "Picking objects needs \(model.name), from Settings › Models."
            return
        }
        guard currentVisit == visit else { return }
        isPickingRegion = true
        defer { isPickingRegion = false }
        do {
            let found = try await engine.computeMasks(request)
            guard currentVisit == visit else { return }
            guard let picked = choose(found) else {
                pickMessage = pick == .person ? "No one is there." : "Nothing was found there."
                return
            }
            let mask = removesShadows ? await engine.withShadowAndReflection(picked) : picked
            guard currentVisit == visit else { return }
            if let target {
                guard let spot = recipe.spots.first(where: { $0.id == target.id }), spot.region == target.region
                else { return }
                let refills = spot.fill != nil || generating?.spot == spot.id
                updateSpot(spot.id, name: "Add to Object") { spot in
                    spot.region = mask
                    spot.center = mask.center
                    spot.source = mask.center
                }
                if refills {
                    refillGeneratively(spot.id)
                }
                return
            }
            let spot = RetouchSpot(
                mode: .remove, center: mask.center, source: mask.center, region: mask, radius: Self.regionGrowth,
                feather: spotSettings.feather, opacity: spotSettings.opacity,
            )
            var next = recipe
            next.spots.append(spot)
            commit(next, .retouch, "Remove \(pick.name)")
            selectedSpotID = spot.id
            fillNewSpotGeneratively(spot)
        } catch {
            guard currentVisit == visit else { return }
            pickMessage = "\(error)"
        }
    }

    /// Whether `stroke` touches the mask in `png`: passes over it, or comes within `reach` (a
    /// fraction of the image height) of where it covers.
    nonisolated static func touches(_ stroke: [ImagePoint], mask png: Data, within reach: Double) -> Bool {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0,
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue,
              )
        else { return false }
        let (width, height) = (image.width, image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        // The mask has the photo's shape, so its pixels are as wide as they are high; the pixel a
        // point is in has its centre within 0.71 of it.
        let radius = max(reach * Double(height), 0.75)
        let span = Int(radius.rounded(.up))
        for point in stroke {
            let (x, y) = (point.x * Double(width), point.y * Double(height))
            let (column, row) = (Int(x.rounded(.down)), Int(y.rounded(.down)))
            let (left, right) = (max(column - span, 0), min(column + span, width - 1))
            let (top, bottom) = (max(row - span, 0), min(row + span, height - 1))
            guard left <= right, top <= bottom else { continue }
            for j in top ... bottom {
                for i in left ... right
                    where pixels[j * width + i] >= 128 && hypot(Double(i) + 0.5 - x, Double(j) + 0.5 - y) <= radius {
                    return true
                }
            }
        }
        return false
    }

    /// `box` grown to take in `points`, within the photo.
    private static func box(_ box: ImageRect, around points: [ImagePoint]) -> ImageRect {
        let xs = points.map(\.x) + [box.x, box.x + box.width]
        let ys = points.map(\.y) + [box.y, box.y + box.height]
        let (left, right) = (max(xs.min() ?? 0, 0), min(xs.max() ?? 1, 1))
        let (top, bottom) = (max(ys.min() ?? 0, 0), min(ys.max() ?? 1, 1))
        return ImageRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The mask covering `point`, or else the one whose middle is nearest.
    internal static func mask(at point: ImagePoint, in masks: [AIMask]) -> AIMask? {
        let covering = masks.first { mask in
            guard let png = mask.bitmap.png, let bitmap = NSBitmapImageRep(data: png) else { return false }
            let x = min(max(Int(point.x * Double(bitmap.pixelsWide)), 0), bitmap.pixelsWide - 1)
            let y = min(max(Int(point.y * Double(bitmap.pixelsHigh)), 0), bitmap.pixelsHigh - 1)
            return (bitmap.colorAt(x: x, y: y)?.whiteComponent ?? 0) >= 0.5
        }
        return covering ?? masks.min { a, b in
            hypot(a.center.x - point.x, a.center.y - point.y) < hypot(b.center.x - point.x, b.center.y - point.y)
        }
    }

    /// Traces the outline of `region`'s mask for the canvas (`regionOutlines`), off the main
    /// thread, once a mask.
    func traceOutline(of region: AIMask) async {
        let bitmap = region.bitmap
        guard let visit = currentVisit, regionOutlines[bitmap.sha256] == nil, let png = bitmap.png else { return }
        let loops = await Task.detached(priority: .userInitiated) { Self.outline(ofMask: png) }.value
        guard currentVisit == visit else { return }
        regionOutlines[bitmap.sha256] = loops
    }

    /// Where a mask crosses half coverage, as closed loops in the photo's coordinates: marching
    /// squares over a copy at most `longEdge` pixels across, each crossing placed between its two
    /// pixels by how much they cover.
    nonisolated static func outline(ofMask png: Data, longEdge: Int = 1024) -> [[ImagePoint]] {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0
        else { return [] }
        let scale = min(Double(longEdge) / Double(max(image.width, image.height)), 1)
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        // A pixel of nothing all round, so a loop that reaches the frame's edge closes along it.
        let (columns, rows) = (width + 2, height + 2)
        guard let context = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue,
        ) else { return [] }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 1, y: 1, width: width, height: height))
        guard let data = context.data else { return [] }
        let pixels = Array(UnsafeBufferPointer(
            start: data.bindMemory(to: UInt8.self, capacity: columns * rows), count: columns * rows,
        ))
        func covers(_ index: Int) -> Bool {
            pixels[index] >= 128
        }
        // A crossing is named by the pixel it leaves: 2i towards the next in its row, 2i + 1
        // towards the one below. Each is linked to the crossing on either side of it.
        var links: [Int: [Int]] = [:]
        func link(_ a: Int, _ b: Int) {
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        for y in 0 ..< rows - 1 {
            for x in 0 ..< columns - 1 {
                let i = y * columns + x
                let corners = (covers(i) ? 8 : 0) | (covers(i + 1) ? 4 : 0) | (covers(i + columns + 1) ? 2 : 0)
                    | (covers(i + columns) ? 1 : 0)
                let (top, bottom, left, right) = (2 * i, 2 * (i + columns), 2 * i + 1, 2 * (i + 1) + 1)
                switch corners {
                case 1, 14: link(left, bottom)
                case 2, 13: link(bottom, right)
                case 3, 12: link(left, right)
                case 4, 11: link(top, right)
                case 6, 9: link(top, bottom)
                case 7, 8: link(left, top)
                case 5, 10:
                    // Opposite corners covered: they join through the middle when it's covered.
                    let middle = Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + columns])
                        + Int(pixels[i + columns + 1])
                    if (corners == 5) == (middle >= 4 * 128) {
                        link(left, top)
                        link(bottom, right)
                    } else {
                        link(top, right)
                        link(left, bottom)
                    }
                default: break
                }
            }
        }
        func point(_ crossing: Int) -> ImagePoint {
            let (i, along) = (crossing / 2, crossing % 2 == 0)
            let (a, b) = (Double(pixels[i]), Double(pixels[along ? i + 1 : i + columns]))
            let t = (127.5 - a) / (b - a)
            let (x, y) = (Double(i % columns) + (along ? t : 0), Double(i / columns) + (along ? 0 : t))
            return ImagePoint(x: (x - 0.5) / Double(width), y: (y - 0.5) / Double(height))
        }
        var loops: [[ImagePoint]] = []
        var walked = Set<Int>()
        for start in links.keys where !walked.contains(start) {
            var loop: [ImagePoint] = []
            var (previous, current) = (start, start)
            repeat {
                guard let ends = links[current], ends.count == 2 else { break }
                walked.insert(current)
                loop.append(point(current))
                (previous, current) = (current, ends[0] == previous ? ends[1] : ends[0])
            } while current != start
            loops.append(loop)
        }
        return loops
    }

    /// Find's lowest score worth outlining: below it OWLv2's boxes are mostly guesses.
    static let findThreshold = 0.25

    /// What Find can look for, once its model is there.
    func loadThingsToFind() async {
        thingsToFind = await engine.thingsToFind()
    }

    /// Outlines each `thingToFind` (every thing, when nil) in the open photo, for a click to remove.
    func findThings() async {
        guard info != nil, !isFindingThings else { return }
        findMessage = nil
        if let model = await engine.modelNeededToFind() {
            findMessage = "Finding things needs \(model.name), from Settings › Models."
            return
        }
        if thingsToFind.isEmpty {
            await loadThingsToFind()
        }
        guard let visit = currentVisit else { return }
        let wanted = thingToFind.map { Set([$0]) } ?? Set(thingsToFind)
        isFindingThings = true
        defer { isFindingThings = false }
        do {
            let found = try await engine.findThings(wanted, threshold: Self.findThreshold)
            guard currentVisit == visit else { return }
            foundThings = found
            findMessage = switch found.count {
            case 0: "Nothing found."
            case 1: "Found 1: click it to remove it."
            default: "Found \(found.count): click one to remove it."
            }
        } catch {
            guard currentVisit == visit else { return }
            findMessage = (error as? MaskComputationError)?.description ?? "\(error)"
        }
    }

    /// Removes a thing Find outlined: Segment Anything cuts its mask from its box, and a Remove
    /// spot fills it, as a picked object's.
    func removeFound(_ found: FoundThing) async {
        guard let spot = await foundSpot(found) else { return }
        var next = recipe
        next.spots.append(spot)
        commit(next, .retouch, "Remove \(found.thing.capitalized)")
        selectedSpotID = spot.id
        fillNewSpotGeneratively(spot)
        foundThings.removeAll { $0.id == found.id }
    }

    /// Removes everything Find outlined, as one step.
    func removeAllFound() async {
        let visit = currentVisit
        var spots: [RetouchSpot] = []
        var removed: Set<UUID> = []
        for found in foundThings {
            guard let spot = await foundSpot(found) else { continue }
            spots.append(spot)
            removed.insert(found.id)
        }
        guard !spots.isEmpty, currentVisit == visit else { return }
        var next = recipe
        next.spots += spots
        commit(next, .retouch, "Remove Everything Found")
        selectedSpotID = nil
        if fillsNewSpotsGeneratively {
            fillGeneratively(spots.map(\.id), variations: 1)
        }
        foundThings.removeAll { removed.contains($0.id) }
    }

    /// A Remove spot shaped by Segment Anything's mask in `found`'s box, grown a little; nil, with
    /// a message saying why, when it can't be made.
    private func foundSpot(_ found: FoundThing) async -> RetouchSpot? {
        guard info != nil, !isPickingRegion else { return nil }
        if let model = await engine.modelNeeded(for: .objects) {
            findMessage = "Removing it needs \(model.name), from Settings › Models."
            return nil
        }
        guard let visit = currentVisit else { return nil }
        isPickingRegion = true
        defer { isPickingRegion = false }
        do {
            guard let thing = try await engine.computeMasks(MaskRequest(kind: .objects, box: found.box)).first,
                  currentVisit == visit
            else { return nil }
            let mask = removesShadows ? await engine.withShadowAndReflection(thing) : thing
            guard currentVisit == visit else { return nil }
            return RetouchSpot(
                mode: .remove, center: mask.center, source: mask.center, region: mask, radius: Self.regionGrowth,
                feather: spotSettings.feather, opacity: spotSettings.opacity,
            )
        } catch {
            guard currentVisit == visit else { return nil }
            findMessage = (error as? MaskComputationError)?.description ?? "\(error)"
            return nil
        }
    }

    /// A new Remove spot, filled generatively when Fill is Generative.
    private func fillNewSpotGeneratively(_ spot: RetouchSpot) {
        if spot.mode == .remove, fillsNewSpotsGeneratively {
            fillGeneratively([spot.id])
        }
    }

    var selectedSpot: RetouchSpot? {
        selectedSpotID.flatMap { id in recipe.spots.first { $0.id == id } }
    }

    /// Adds a spot at `center` with the tool's settings, copying from the source the engine finds.
    func addSpot(at center: ImagePoint) async {
        guard let visit = currentVisit else { return }
        var spot = RetouchSpot(
            mode: spotMode, center: center, source: center, radius: RetouchSpot.radius(size: spotSettings.size),
            feather: spotSettings.feather, opacity: spotSettings.opacity,
        )
        if spot.mode.usesSource {
            spot.source = await engine.retouchSource(for: spot, recipe: recipe) ?? nearbySource(for: spot)
            guard currentVisit == visit else { return }
        }
        var next = recipe
        next.spots.append(spot)
        commit(next, .retouch, spot.mode.name)
        selectedSpotID = spot.id
        fillNewSpotGeneratively(spot)
    }

    /// Adds a brushed spot along `points`, painted with the tool's settings; a stroke too short to
    /// be one adds a circle.
    func addStroke(_ points: [ImagePoint]) async {
        guard let visit = currentVisit, let first = points.first else { return }
        let radius = RetouchSpot.radius(size: spotSettings.size)
        let aspect = Double(info?.pixelSize.width ?? 1) / Double(max(info?.pixelSize.height ?? 1, 1))
        // A quarter of the brush apart is plenty to follow the hand.
        var kept = [first]
        for point in points.dropFirst() {
            let last = kept[kept.count - 1]
            if hypot((point.x - last.x) * aspect, point.y - last.y) >= radius / 4 {
                kept.append(point)
            }
        }
        guard kept.count > 1 else {
            await addSpot(at: first)
            return
        }
        var spot = RetouchSpot(
            mode: spotMode, center: first, source: first,
            stroke: kept.dropFirst().map { ImagePoint(x: $0.x - first.x, y: $0.y - first.y) },
            radius: radius, feather: spotSettings.feather, opacity: spotSettings.opacity,
        )
        if spot.mode.usesSource {
            spot.source = await engine.retouchSource(for: spot, recipe: recipe) ?? nearbySource(for: spot)
            guard currentVisit == visit else { return }
        }
        var next = recipe
        next.spots.append(spot)
        commit(next, .retouch, "\(spot.mode.name) Brush")
        selectedSpotID = spot.id
        fillNewSpotGeneratively(spot)
    }

    /// Heals every speck of sensor dust the engine finds, in one step.
    func removeDust() async {
        guard let visit = currentVisit, !isFindingDust else { return }
        isFindingDust = true
        defer { isFindingDust = false }
        let found = await engine.detectDust(recipe: recipe, sensitivity: 50)
        guard currentVisit == visit else { return }
        guard !found.isEmpty else {
            dustMessage = "No dust found."
            return
        }
        var spots: [RetouchSpot] = []
        for speck in found {
            var spot = RetouchSpot(center: speck.center, source: speck.center, radius: speck.radius)
            spot.source = await engine.retouchSource(for: spot, recipe: recipe) ?? nearbySource(for: spot)
            spots.append(spot)
        }
        guard currentVisit == visit else { return }
        var next = recipe
        next.spots += spots
        commit(next, .retouch, "Remove Dust")
        selectedSpotID = nil
        dustMessage = spots.count == 1 ? "Healed 1 speck of dust." : "Healed \(spots.count) specks of dust."
    }

    /// Remove Dust across the selection: the specks found in the same place on the sensor in
    /// several of its photos are healed in all of them, the photo open in the editor as a step of its
    /// own history, the others as one batch Undo can put back (`SettingsSync`). Dust is the sensor's, the same in each
    /// of a file's edits (LIB-48): each file is looked at once, in the edit of it first among them, and what's found
    /// is healed in each.
    func removeDustInSelection() async {
        guard isMultiSelecting, let open = openPhoto, !isFindingDust, settingsSync.progress == nil else {
            return
        }
        let chosen = selectionForAction()
        saveNow()
        isFindingDust = true
        defer {
            isFindingDust = false
            dustSearch = nil
        }
        let openRecipe = recipe
        dustSearch = SettingsSync.Progress(title: "Finding Dust", done: 0, total: chosen.count)
        // A large source's photos are found by their IDs, off the main thread, their rows left unread.
        let selected = await chosen.all()
        let targets = [open] + selected.filter { $0 != open }
        let files = SettingsSync.byFile(targets)
        let others = files.map(\.url).filter { $0 != open.url }
        for url in others {
            await saves.wait(for: url)
        }
        let store = settingsSync.store
        let reads = await Task.detached {
            Dictionary(others.map { url in (url, Result { try store.loadThrowing(for: url) }) }) { first, _ in first }
        }.value
        // A photo whose edit can't be read is left out: its dust would be looked for in the wrong
        // edit, and the batch leaves it alone anyway.
        let photos = files.compactMap { file -> (url: URL, recipe: EditRecipe)? in
            guard file.url != open.url else { return (file.url, openRecipe) }
            guard case let .success(sidecar)? = reads[file.url], let first = file.photos.first,
                  let edit = sidecar.map({ $0[edit: first.version]?.recipe }) ?? (first.version == nil
                      ? EditRecipe() : nil)
            else { return nil }
            return (file.url, edit)
        }
        dustSearch = SettingsSync.Progress(title: "Finding Dust", done: 0, total: photos.count)
        let finder = makeWorkerEngine?() ?? engine
        let found = await finder.detectDust(in: photos, sensitivity: 50) { [weak self] done in
            Task { @MainActor in self?.dustSearch?.done = done }
        }
        let specks = Set(found.values.flatMap { $0.map { "\($0.center.x),\($0.center.y)" } }).count
        guard !found.isEmpty else {
            dustMessage = "No dust found in the same place in two or more photos."
            return
        }
        // Whichever photo is open when the batch reaches it is healed in the editor, not behind it.
        var healed: Set<PhotoAddress> = []
        settingsSync.run(.healDust(found), on: targets, title: "Remove Dust") { [weak self] photo, recipe in
            healed.insert(photo)
            self?.written(photo, recipe)
        }
        dustSearch = nil
        // Still finding dust until the batch is done: it heals the open photo in the editor too.
        await settingsSync.idle()
        dustMessage = healed.isEmpty
            ? "The dust found couldn't be healed."
            : "Healed \(specks == 1 ? "1 speck" : "\(specks) specks") of dust in \(healed.count == 1 ? "1 photo" : "\(healed.count) photos")."
    }

    /// Heals `specks` in `url` as a step of its history when it is the photo open; false when it
    /// isn't, or stops being open before its sources are found.
    func healDustInEditor(_ specks: [DetectedSpot], on url: URL) async -> Bool {
        guard let visit = currentVisit, visit.url == url else { return false }
        var spots: [RetouchSpot] = []
        for speck in specks {
            var spot = RetouchSpot(center: speck.center, source: speck.center, radius: speck.radius)
            spot.source = await engine.retouchSource(for: spot, recipe: recipe) ?? nearbySource(for: spot)
            guard currentVisit == visit else { return await healDustInEditor(specks, on: url) }
            spots.append(spot)
        }
        guard !spots.isEmpty else { return true }
        var next = recipe
        next.spots += spots
        commit(next, .retouch, "Remove Dust")
        return true
    }

    /// Changes a spot as part of a drag (between `beginEdit` and `endEdit`), or as one step.
    func updateSpot(_ id: UUID, name: String? = nil, _ change: (inout RetouchSpot) -> Void) {
        guard let index = recipe.spots.firstIndex(where: { $0.id == id }) else { return }
        var next = recipe
        change(&next.spots[index])
        dropMovedFill(&next.spots[index])
        if let name, editStart == nil {
            commit(next, .retouch, name)
        } else {
            applyLive(next)
        }
    }

    func deleteSpot(_ id: UUID) {
        var next = recipe
        next.spots.removeAll { $0.id == id }
        commit(next, .retouch, "Delete Spot")
        if selectedSpotID == id {
            selectedSpotID = nil
        }
    }

    func deleteAllSpots() {
        var next = recipe
        next.spots = []
        commit(next, .retouch, "Delete All Spots")
        selectedSpotID = nil
    }

    /// Remove, Heal or Clone for the next spot, and for the selected one. A Remove spot becoming
    /// Heal or Clone finds a source first.
    func setSpotMode(_ mode: RetouchSpot.Mode) async {
        spotMode = mode
        guard var spot = selectedSpot, let visit = currentVisit else { return }
        spot.mode = mode
        if mode.usesSource, spot.source == spot.center {
            var earlier = recipe
            earlier.spots = Array(recipe.spots.prefix { $0.id != spot.id })
            spot.source = await engine.retouchSource(for: spot, recipe: earlier) ?? nearbySource(for: spot)
            guard currentVisit == visit else { return }
        }
        let changed = spot
        updateSpot(spot.id, name: mode.name) { $0 = changed }
    }

    /// Asks the engine for a source again, as if the selected spot had just been placed.
    func findNewSource() async {
        guard let spot = selectedSpot, spot.mode.usesSource, let visit = currentVisit else { return }
        var earlier = recipe
        earlier.spots = Array(recipe.spots.prefix { $0.id != spot.id })
        guard let source = await engine.retouchSource(for: spot, recipe: earlier), currentVisit == visit
        else { return }
        updateSpot(spot.id, name: "New Source") { $0.source = source }
    }

    internal func spotValue(_ parameter: ParameterID) -> Double {
        guard parameter != .spotVisualize else { return spotSettings.visualize }
        return selectedSpot?[parameter] ?? spotSettings[parameter]
    }

    /// The selected spot's setting, and the next spot's.
    internal func setSpotValue(_ parameter: ParameterID, _ value: Double) {
        spotSettings[parameter] = value
        guard parameter != .spotVisualize else {
            requestRender()
            return
        }
        guard let id = selectedSpotID else { return }
        let value = spotSettings[parameter]
        updateSpot(id, name: editStart == nil ? "Spot \(parameter.spec.label)" : nil) { spot in
            switch parameter {
            case .spotSize: spot.radius = RetouchSpot.radius(size: value)
            case .spotFeather: spot.feather = value
            case .spotOpacity: spot.opacity = value
            default: break
            }
        }
    }

    /// Two and a half radii to the side of a circle, or below (or above) a stroke, when the engine
    /// finds nothing better.
    private func nearbySource(for spot: RetouchSpot) -> ImagePoint {
        guard spot.stroke.isEmpty else {
            let ys = spot.points().map(\.y)
            let step = (ys.max() ?? 0) - (ys.min() ?? 0) + spot.radius * 2.5
            let below = (ys.max() ?? 0) + step + spot.radius <= 1
            return ImagePoint(x: spot.center.x, y: spot.center.y + (below ? step : -step))
        }
        let size = info?.pixelSize ?? PixelSize(width: 1, height: 1)
        let aspect = Double(size.height) / Double(max(size.width, 1))
        let step = spot.radius * 2.5 * aspect
        let x = spot.center.x + step <= 1 - spot.radius * aspect ? spot.center.x + step : spot.center.x - step
        return ImagePoint(x: x, y: spot.center.y)
    }
}
