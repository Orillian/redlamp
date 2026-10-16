#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampDocument
    import RedlampEngineAPI
    @_spi(Harness) import RedlampLibrary
    @_spi(Harness) import RedlampUI

    /// Lightroom's edits in photos' XMP (EDT-12), from `.xmp` files the run writes from the format note
    /// (`docs/research/notes/EDT-lightroom-develop-settings.md`): never ones Lightroom made.
    enum LightroomSidecarScenarios {
        static let all: [Scenario] = [sidecars]

        static let sidecars = Scenario(
            "library.lightroom-sidecars",
            "Library › Convert Lightroom Edits… reports a folder's Lightroom edits before writing anything, converts "
                + "the photos with none in Redlamp, leaves an edited one as it is, and Undo Sync Settings takes the "
                + "conversion back; a photo opened in Develop then opens with its edit converted and the provenance "
                + "notice",
            claims: [.action(.convertLightroomEdits)],
        ) { app in
            let scratch = try SourcesScratch(
                app, photos: ["LR_0001.jpg", "LR_0002.jpg", "LR_0003.jpg", "LR_0004.jpg"],
            )
            defer { scratch.remove(app) }
            for (name, exposure) in [("LR_0001", "+0.40"), ("LR_0002", "-0.30"), ("LR_0004", "+0.85")] {
                try Data(xmp(exposure: exposure).utf8).write(to: scratch.folder.appending(path: "\(name).xmp"))
            }
            let sidecars = SidecarStore(locator: .besidePhotos)
            let photos = scratch.names.map(scratch.photo)
            var edited = EditRecipe()
            edited[.contrast] = 30
            try sidecars.save(Sidecar(recipe: edited), for: photos[1])
            try scratch.index(app)
            try app.click(.identifier("grid.\(scratch.names[0])"))
            try app.wait("the first photo active", timeout: 10) { $0.selection == photos[0] }

            try app.choose(.convertLightroomEdits)
            try app.wait("the report", timeout: 60) { $0.lightroomConversion?.scan != nil }
            let scan = try app.main { $0.lightroomConversion?.scan }
            try app.expect(
                scan?.conversions.map(\.photo) == [photos[0], photos[3]] && scan?.edited == [photos[1]],
                "the report: \(scan?.lines.joined(separator: " / ") ?? "none")",
            )
            try app.expect(
                sidecars.load(for: photos[0]) == nil && sidecars.load(for: photos[3]) == nil,
                "the report wrote nothing",
            )
            try app.expect(try app.pressInSheet(KeyCombo(.return)), "Convert took Return")
            try app.wait("the conversion", timeout: 120) { model in
                if case .done? = model.lightroomConversion?.stage {
                    true
                } else {
                    false
                }
            }
            let provenance = sidecars.load(for: photos[0])?.recipe.provenance
            try app.expect(
                provenance?.source == .xmpSidecar && sidecars.load(for: photos[3])?.recipe[.exposure] == 0.85,
                "the converted edits: \(String(describing: provenance))",
            )
            try app.expect(sidecars.load(for: photos[1])?.recipe == edited, "the photo edited in Redlamp kept its edit")
            try app.expect(try app.pressInSheet(KeyCombo(.return)), "Done took Return")
            try app.wait("the sheet closed", timeout: 10) { $0.lightroomConversion == nil }

            try app.choose(.undoSync)
            try app.wait("the conversion taken back", timeout: 60) { _ in
                sidecars.load(for: photos[0]) == nil && sidecars.load(for: photos[3]) == nil
            }

            try app.click(.identifier("grid.\(scratch.names[3])"))
            try app.choose(.developModule)
            try app.wait("the photo open in Develop", timeout: 60) { $0.info?.url == photos[3] }
            let opened = try app.main { model in
                (model.recipe[.exposure], model.history.first?.title, model.provenanceNotice?.title)
            }
            try app.expect(
                opened.0 == 0.85 && opened.1 == "Converted from Lightroom"
                    && opened.2 == "From Lightroom’s XMP sidecar: every setting converted",
                "opened: \(opened)",
            )
            try app.wait("the provenance notice", timeout: 10) { _ in
                (try? app.exists(.identifier("provenance.notice"))) == true
            }
            try app.wait("the converted edit saved", timeout: 30) { _ in
                sidecars.load(for: photos[3])?.recipe.provenance != nil
            }
            app.covered(.action(.convertLightroomEdits), via: .menu)
        }

        /// A photo's develop settings in an `.xmp` beside it, as Lightroom Classic writes them.
        private static func xmp(exposure: String) -> String {
            """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
             <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about=""
                xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
                xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
               tiff:Make="Example"
               crs:Version="15.4"
               crs:ProcessVersion="11.0"
               crs:WhiteBalance="As Shot"
               crs:Exposure2012="\(exposure)"
               crs:HasSettings="True"
               crs:HasCrop="False"/>
             </rdf:RDF>
            </x:xmpmeta>
            """
        }
    }
#endif
