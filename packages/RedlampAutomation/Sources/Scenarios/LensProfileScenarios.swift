#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampDesign
    import RedlampEngineAPI
    @_spi(Harness) import RedlampUI

    /// Choosing a lens profile by hand (LNS-15), in the Lens Corrections panel's menus.
    enum LensProfileScenarios {
        /// The working photo's camera and frame: the Sony ILCE-7M3 sample.
        static func profile(lens: String, prettyName: String, focalLength: Double) -> String {
            """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
             xmlns:stCamera="http://ns.adobe.com/photoshop/1.0/camera-profile"><photoshop:CameraProfiles><rdf:Seq>
            <rdf:li><rdf:Description stCamera:Make="SONY" stCamera:Model="ILCE-7M3" stCamera:Lens="\(lens)"
             stCamera:LensPrettyName="\(prettyName)" stCamera:ProfileName="Scenario (\(prettyName))"
             stCamera:CameraRawProfile="True" stCamera:ImageWidth="6024" stCamera:ImageLength="4024"
             stCamera:SensorFormatFactor="1" stCamera:FocalLength="\(focalLength)" stCamera:ApertureValue="2">
            <stCamera:PerspectiveModel><rdf:Description stCamera:FocalLengthX="1.2" stCamera:FocalLengthY="1.2"
             stCamera:RadialDistortParam1="-0.08"><stCamera:VignetteModel><rdf:Description stCamera:FocalLengthX="1.2"
             stCamera:FocalLengthY="1.2" stCamera:VignetteModelParam1="-0.6"/></stCamera:VignetteModel>
            </rdf:Description></stCamera:PerspectiveModel></rdf:Description></rdf:li></rdf:Seq>
            </photoshop:CameraProfiles></rdf:Description></rdf:RDF></x:xmpmeta>
            """
        }

        static let choice = Scenario(
            "develop.lens-profile-choice",
            "A lens profile chosen by hand in the Lens Corrections panel's Make menu, Auto from its Setup menu, and a "
                + "named profile that isn't on the Mac reported with what stands in",
            claims: [.feature("develop.lens-corrections")],
            needsFocus: true,
        ) { app in
            // The home the suite runs in has its own Lens Profiles folder.
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            else { throw ScenarioFailure("No Application Support folder") }
            let folder = support.appending(path: "Redlamp/Lens Profiles/Scenario", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data(profile(lens: "Helios 44-2 58mm f/2", prettyName: "Helios 44-2 58mm f/2", focalLength: 58).utf8)
                .write(to: folder.appending(path: "Helios.lcp"))
            try Data(profile(lens: "Batis 2/25", prettyName: "Zeiss Batis 2/25", focalLength: 25).utf8)
                .write(to: folder.appending(path: "Batis.lcp"))

            // A photo's profiles are found when it opens: one open already is opened again.
            let working = try app.workingPhoto()
            if try app.main({ $0.selection?.lastPathComponent }) == working {
                guard let other = try app.photoNames().first(where: { $0 != working }) else {
                    throw ScenarioFailure("The folder has no photo besides \(working)")
                }
                try app.open(other)
            }
            try app.open(working)
            try app.main { $0.expandedPanels.insert(.lens) }
            try app.wait("the photo's lens profiles found", timeout: 20) { model in
                Set((model.lensProfileOptions ?? []).map(\.fileName)).isSuperset(of: ["Helios.lcp", "Batis.lcp"])
            }
            try app.focus()
            try app.expectRenders("the Helios's profile, chosen by its make") {
                try app.chooseLensProfile("Helios", in: "Make") { model in
                    model.lensProfileSetup == .custom && model.recipe.lensProfileChoice?.fileName == "Helios.lcp"
                }
            }
            try app
                .chooseLensProfile("Auto", in: "Setup") {
                    $0.recipe.lensProfileChoice == LensProfileChoice(setup: .auto)
                }
            try app
                .main { $0.setLensProfileChoice(LensProfileChoice(setup: .custom, name: "Gone", fileName: "Gone.lcp")) }
            try app.wait("the panel to say the profile isn't on this Mac") {
                $0.missingLensProfileText == "Profile not on this Mac: Gone"
            }
            try app.choose(.resetAll)
            app.covered(.feature("develop.lens-corrections"), via: .mouse)
        }
    }

    extension RunningApp {
        /// Chooses `title` in the Lens Corrections panel's lens profile menu `menu` (Setup, Make,
        /// Model or Profile) with a click on it and the keyboard in the menu that opens, as a click on
        /// the item does, and waits until `done`.
        func chooseLensProfile(
            _ title: String, in menu: String, until done: @escaping @MainActor (EditorModel) -> Bool,
        ) throws {
            _ = try main { _ in try Self.lensProfileMenu(menu) }
            let opened = OpenedMenu()
            try main { _ in opened.watch { menu in opened.chose = Menus.chooseByKeys(title, in: menu) } }
            defer { try? main { _ in opened.stop() } }
            // The menu tracks inside the press.
            post { _ in
                guard let picker = try? Self.lensProfileMenu(menu) else { return }
                Views.tap(at: picker.point, inWindow: picker.window, clicks: 1, modifiers: [])
            }
            try wait("the lens profile \(menu) menu to open") { _ in opened.menu != nil }
            try wait("the lens profile \(menu) menu to close") { _ in opened.closed }
            let (items, chose) = try main { _ in (opened.items.map(\.title), opened.chose) }
            try expect(chose, "The lens profile \(menu) menu has no \(title): \(items)")
            try wait("\(title) in the lens profile \(menu) menu", until: done)
        }

        /// Where a lens profile menu is, scrolled into view: its window and the middle of its picker.
        /// The four menus are the Lens Corrections panel's rows before its Distortion slider, each a
        /// `ControlRow`: its label, `Metrics.labelWidth` wide, then the picker after
        /// `Metrics.rowSpacing`. macOS 27's SwiftUI draws the pickers with no AppKit control under
        /// them to find them by, as the firmware model's are found.
        @MainActor static func lensProfileMenu(_ menu: String) throws -> (window: Int, point: NSPoint) {
            let menus = ["Setup", "Make", "Model", "Profile"]
            guard let offset = menus.firstIndex(of: menu), let window = Views.editorWindow,
                  let panel = Views.shown("panel.lens", in: window)
            else { throw ScenarioFailure("The Lens Corrections panel shows no \(menu) menu") }
            let slider = Target.slider(.lensProfileDistortion).identifier
            var view = Views.all(NSView.self, in: panel).first { $0.accessibilityIdentifier() == slider }
            while let row = view {
                if let column = row.superview as? ColumnView, let index = column.arrangedViews.firstIndex(of: row) {
                    let position = index - menus.count + offset
                    guard position >= 0 else { break }
                    let picker = column.arrangedViews[position]
                    picker.scrollToVisible(picker.bounds)
                    window.contentView?.layoutSubtreeIfNeeded()
                    let frame = picker.convert(picker.bounds, to: nil)
                    return (
                        window.windowNumber,
                        NSPoint(x: frame.minX + Metrics.labelWidth + Metrics.rowSpacing + 16, y: frame.midY),
                    )
                }
                view = row.superview
            }
            throw ScenarioFailure("The Lens Corrections panel's Distortion slider isn't in its column")
        }
    }
#endif
