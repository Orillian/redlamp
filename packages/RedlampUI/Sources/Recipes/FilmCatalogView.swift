import CoreGraphics
import RedlampDesign
import RedlampEngineAPI
import RedlampRecipes
import SwiftUI

/// The Film Looks window: every film stock look as a card showing the current photo in it.
/// Hover previews a look in the editor; click chooses it as the Base Looks panel does, with its
/// grain, halation and bloom and nothing else (DEC-104). Holding Option over a card shows the photo
/// before the look. Previews render one after another at low priority, so the editor stays responsive.
public struct FilmCatalogView: View {
    public static let windowID = "film-looks"

    @Environment(EditorModel.self) private var model
    @State private var previews: [String: CGImage] = [:]
    @State private var before: CGImage?
    @State private var filter = Filter.all
    @State private var hovered: String?
    @State private var comparing = false

    public init() {}

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case favourites = "Favourites"
        case colour = "Colour Negative"
        case cinema = "Cinema"
        case slide = "Slide"
        case monochrome = "Black & White"

        var id: String {
            rawValue
        }

        func includes(_ look: FilmLookDefinition, favourite: Bool) -> Bool {
            switch self {
            case .all: true
            case .favourites: favourite
            case .colour: !look.isMonochrome && look.icon.shape == .canister && !look.film.contains("cinestill")
            case .cinema: look.icon.shape == .reel || look.film.contains("cinestill")
            case .slide: look.icon.shape == .slide
            case .monochrome: look.isMonochrome
            }
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 16, alignment: .top)]
    private static let previewEdge = 640

    public var body: some View {
        let entries = FilmLookCatalog.browsingOrder.compactMap { look in
            model.recipes.recipe(id: look.recipeID).map { (look, $0) }
        }
        let shown = entries.filter { filter.includes($0.0, favourite: model.recipes.isFavorite($0.1)) }
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
                    ForEach(shown, id: \.0.id) { look, recipe in
                        card(look, recipe)
                    }
                }
                .padding(16)
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No film looks installed", systemImage: "film",
                        description: Text("This build doesn't bundle the film stock tables."),
                    )
                } else if shown.isEmpty, filter == .favourites {
                    ContentUnavailableView(
                        "No favourites yet", systemImage: "star",
                        description: Text("Click a card's star to keep it here."),
                    )
                }
            }
            .overlayScrollers()
        }
        .task(id: model.info?.url) {
            previews = [:]
            before = nil
            await renderPreviews(entries.map(\.0))
        }
        .onModifierKeysChanged(mask: .option) { _, keys in
            comparing = keys.contains(.option)
            if comparing, before == nil {
                Task { await renderBefore() }
            }
        }
        .onDisappear { model.previewRecipe(nil) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Film Looks").font(.title2.weight(.semibold))
                Text(model.info == nil
                    ? "Open a photo to see it in each film."
                    : "Hover to preview in the editor, click to apply, hold ⌥ to compare with the photo before.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let film = Self.film(of: model.baseLook) {
                let amount = model.baseLook.amount
                HStack(spacing: 8) {
                    Text(film.name).font(.callout)
                    Slider(
                        value: Binding(get: { amount }, set: { model.setBaseLookAmount($0) }),
                        in: BaseLookReference.amountRange,
                        onEditingChanged: { editing in
                            if editing {
                                model.beginEdit()
                            } else {
                                model.endEdit(.baseLook, "Base Look Amount", value: EditorModel.baseLookAmountText)
                            }
                        },
                    )
                    .frame(width: 160)
                    Text("\(Int(amount.rounded()))").monospacedDigit().frame(width: 32, alignment: .trailing)
                }
                .help("The Base Look's Amount, as in Basic")
            }
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// The film stock whose look the edit's `look` is.
    static func film(of look: BaseLookReference) -> FilmLookDefinition? {
        FilmLookCatalog.look(forBaseLookID: look.id)
    }

    private func card(_ look: FilmLookDefinition, _ recipe: Recipe) -> some View {
        let applied = Self.film(of: model.baseLook)?.id == look.id
        let favourite = model.recipes.isFavorite(recipe)
        let showsBefore = comparing && hovered == look.id
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3))
                if let image = showsBefore ? before : previews[look.id] {
                    Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
                } else if model.info != nil {
                    ProgressView().controlSize(.small)
                } else if let icon = LookIconImage.image(for: look, points: 96) {
                    Image(nsImage: icon)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(applied ? Color.accentColor : hovered == look.id ? Color.secondary : .clear, lineWidth: 2),
            )
            .overlay(alignment: .topLeading) {
                if showsBefore {
                    Text("Before").font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    model.recipes.setFavorite(recipe, !favourite)
                } label: {
                    Image(systemName: favourite ? "star.fill" : "star")
                        .foregroundStyle(favourite ? Color.yellow : Color.white.opacity(0.85))
                        .shadow(radius: 2)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .opacity(favourite || hovered == look.id ? 1 : 0)
                .help(favourite ? "Remove from Favourites" : "Add to Favourites")
            }
            HStack(alignment: .center, spacing: 10) {
                if let icon = LookIconImage.image(for: look, points: 36) {
                    Image(nsImage: icon)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(look.name).font(.headline)
                    Text("\(look.maker) · \(look.format)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if applied {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        .help("Applied to this photo")
                }
            }
            Text(look.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            if applied {
                effectSliders
            } else {
                Text(effectsLine(look)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovered == look.id ? 0.07 : 0.04)))
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside ? look.id : (hovered == look.id ? nil : hovered)
            guard model.info != nil else { return }
            model.previewLook(inside && !applied ? LookChoice(film: look) : nil)
        }
        .onTapGesture {
            guard model.info != nil, !applied, let choice = LookChoice(film: look) else { return }
            model.chooseLook(choice)
        }
        .help(model.info == nil ? look.summary : applied ? look.summary : "Click to apply \(look.name)")
    }

    /// The applied look's film effects, adjustable here as in the Effects panel.
    private var effectSliders: some View {
        VStack(spacing: 2) {
            ForEach([ParameterID.grainAmount, .halationAmount, .bloomAmount], id: \.self) { parameter in
                HStack(spacing: 8) {
                    Text(parameter == .grainAmount ? "Grain" : parameter == .halationAmount ? "Halation" : "Bloom")
                        .font(.caption).frame(width: 52, alignment: .leading)
                    Slider(
                        value: Binding(get: { model.recipe[parameter] }, set: { model.setValue(parameter, $0) }),
                        in: parameter.spec.range,
                        onEditingChanged: { editing in editing ? model.beginEdit(parameter) : model.endEdit() },
                    )
                    .controlSize(.mini)
                    Text("\(Int(model.recipe[parameter]))").font(.caption.monospacedDigit())
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private func effectsLine(_ look: FilmLookDefinition) -> String {
        let parts: [(String, ParameterID)] = [
            ("Grain", .grainAmount),
            ("Halation", .halationAmount),
            ("Bloom", .bloomAmount),
        ]
        return parts.compactMap { name, parameter in
            look.effects[parameter].map { "\(name) \(Int($0))" }
        }.joined(separator: " · ")
    }

    /// Each film over the photo's edit, as choosing it would apply it.
    private func renderPreviews(_ looks: [FilmLookDefinition]) async {
        guard model.info != nil else { return }
        for look in looks where previews[look.id] == nil {
            if Task.isCancelled {
                return
            }
            guard let choice = LookChoice(film: look) else { continue }
            var request = StillRequest(recipe: model.applying(choice, to: model.recipe))
            request.maxLongEdge = Self.previewEdge
            if let image = try? await model.engine.renderStill(request) {
                previews[look.id] = image
            }
            await Task.yield()
        }
    }

    /// The photo before any film look: while its look is a film stock, on Redlamp Color, in colour,
    /// without the film's grain, halation and bloom; otherwise the edit as it is.
    private func renderBefore() async {
        guard model.info != nil else { return }
        let edit = Self.film(of: model.baseLook) == nil
            ? model.anchored(model.recipe)
            : model.applying(LookChoice(BuiltInBaseLook.color.reference), to: model.recipe)
        var request = StillRequest(recipe: edit)
        request.maxLongEdge = Self.previewEdge
        before = try? await model.engine.renderStill(request)
    }
}
