#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampEngineAPI
    @_spi(Harness) import RedlampUI

    enum AcknowledgementsScenarios {
        static let all: [Scenario] = [opens]

        @MainActor private static var controller: AcknowledgementsWindowController? {
            NSApp.windows.lazy.compactMap { $0.windowController as? AcknowledgementsWindowController }
                .first { $0.window?.isVisible == true }
        }

        static let opens = Scenario(
            "help.acknowledgements",
            "Acknowledgements opens from the Help menu on Redlamp's licence, with every component's licence text, "
                + "each downloadable model's licence and the trademark notices",
            claims: [],
        ) { app in
            try app.openWorking()
            try app.choose(AcknowledgementsWindowController.menuTitle)
            try app.wait("the Acknowledgements window") { _ in controller != nil }
            try app.wait("the window to list the downloadable models", timeout: 20) { _ in
                controller?.model.models != nil
            }
            let (selection, missing, models) = try app.main { _ in
                let model = controller?.model
                let texts = [Acknowledgements.redlampLicence] + (model?.components.flatMap(\.texts) ?? [])
                return (
                    model?.selection, texts.filter { $0.contents() == nil }.map(\.file),
                    model?.models ?? [],
                )
            }
            try app.expect(selection == .redlamp, "The window opened on \(String(describing: selection))")
            try app.expect(missing.isEmpty, "The app doesn't bundle \(missing.joined(separator: ", "))")
            for info in models {
                switch ModelLicence(info) {
                case .downloaded, .withDownload:
                    break
                case let .byName(page, _):
                    try app.expect(
                        info.licence != nil && page != nil, "\(info.name) shows neither its licence nor its page",
                    )
                }
            }
            try app.main { _ in
                controller?.model.selection = .trademarks
            }
            app.pause(0.3)
            try app.main { _ in controller?.close() }
            try app.wait("the Acknowledgements window to close") { _ in controller == nil }
        }
    }
#endif
