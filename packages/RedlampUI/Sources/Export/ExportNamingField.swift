import AppKit
import RedlampDocument
import RedlampLibrary
import SwiftUI

/// The naming template field Rename Photos and the import window share (`NamingTemplateField`, LIB-25), in the
/// Export dialog's form: its presets, the template's text with Insert Token beside it, and its error in words.
struct ExportNamingField: NSViewRepresentable {
    let store: NamingPresetStore?
    @Binding var naming: ExportNaming
    let problem: String?

    /// Redlamp's own name for an export first, then the templates renaming and importing offer.
    static let presets: [(String, NamingTemplate)] = [("Filename with Suffix", ExportNaming.standard)].compactMap {
        name, text in (try? NamingTemplate(parsing: text)).map { (name, $0) }
    } + NamingPreset.builtIn.map { ($0.name, $0.template) }

    final class Coordinator {
        var naming: Binding<ExportNaming>
        var field: NamingTemplateField?

        init(naming: Binding<ExportNaming>) {
            self.naming = naming
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(naming: $naming)
    }

    func makeNSView(context: Context) -> NSStackView {
        let coordinator = context.coordinator
        let field = NamingTemplateField(
            identifier: "export.naming", placeholder: ExportNaming.standard, presets: Self.presets, store: store,
        )
        field.text = naming.template
        field.onChange = { text, options in
            coordinator.naming.wrappedValue.template = text
            if let options {
                coordinator.naming.wrappedValue.sequenceStart = options.sequenceStart
            }
        }
        field.options = { NamingOptions(sequenceStart: coordinator.naming.wrappedValue.sequenceStart) }
        coordinator.field = field
        let stack = NSStackView(views: field.rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for row in field.rows.dropFirst() {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    func updateNSView(_: NSStackView, context: Context) {
        context.coordinator.naming = $naming
        context.coordinator.field?.text = naming.template
        context.coordinator.field?.show(error: problem)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSStackView, context _: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: nsView.fittingSize.height)
    }
}
