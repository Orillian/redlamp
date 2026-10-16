import AppKit
import Foundation
import RedlampDocument
@_spi(Harness) import RedlampEngineAPI
import RedlampLibrary
import RedlampRecipes
import Testing
@_spi(Harness) @testable import RedlampUI

/// The Lightroom Classic window's first screen (EDT-34): the catalog Lightroom last used, the presets in Camera Raw's
/// Settings folder and the Adobe camera and lens profiles, each found in a home made for the test, with synthetic
/// files only, present and missing; then the window opening on them, importing the presets and going on to the
/// catalog's report.
@MainActor
@Suite(.serialized)
struct LightroomSetupTests {
    /// A home and a Camera Raw folder of the test's own, removed with what was made in them.
    final class Home {
        let base = LibrarySandbox.scratch.appending(
            path: "lightroom-setup-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )

        var locations: LightroomSetup.Locations {
            LightroomSetup.Locations(
                home: base.appending(path: "Home", directoryHint: .isDirectory),
                cameraRaw: base.appending(
                    path: "Library/Application Support/Adobe/CameraRaw",
                    directoryHint: .isDirectory,
                ),
                lensProfiles: base.appending(path: "Home/Library/Application Support/Redlamp/Lens Profiles"),
            )
        }

        @discardableResult
        func write(_ data: Data, to url: URL) throws -> URL {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: url)
            return url
        }

        @discardableResult
        func write(_ text: String, to url: URL) throws -> URL {
            try write(Data(text.utf8), to: url)
        }

        func remove() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// A develop preset as Lightroom Classic writes one, made up.
    static func preset(_ name: String) -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           crs:PresetType="Normal" crs:UUID="\(UUID().uuidString)" crs:Version="15.0" crs:ProcessVersion="11.0"
           crs:Exposure2012="+0.50" crs:Contrast2012="+10">
           <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">\(name)</rdf:li></rdf:Alt></crs:Name>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    /// A photo's sidecar, which holds Camera Raw settings but isn't a preset.
    static let sidecar = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
       xmlns:tiff="http://ns.adobe.com/tiff/1.0/" tiff:Make="Canon" crs:RawFileName="IMG_0001.CR3"
       crs:Exposure2012="+1.00"/>
     </rdf:RDF>
    </x:xmpmeta>
    """

    static let dcp = SyntheticCameraProfiles.dcp(
        name: "Synthetic Standard", camera: "Canon EOS R5",
        colorMatrices: [
            [0.7, -0.1, -0.05, -0.4, 1.2, 0.2, -0.1, 0.2, 0.6],
            [0.8, -0.2, 0, -0.4, 1.2, 0.2, 0, 0.1, 0.7],
        ],
    )

    static func look(_ name: String) -> Data {
        SyntheticCameraProfiles.xmpLook(name: name)
    }

    /// The startup preferences Lightroom Classic writes on a Mac, naming `load` and then `recent`.
    static func startupPreferences(load: String, recent: [String]) -> String {
        func lua(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let table = "recentLibraries = {\n" + recent.map { "\t\"\(lua($0))\",\n" }.joined() + "}\n"
        return """
        prefs = {
        \tAgLibrary_upgradedCatalogs = "",
        \tlibraryToLoad20 = "\(lua(load))",
        \trecentLibraries20 = "\(lua(table).replacingOccurrences(of: "\n", with: "\\\n"))",
        }
        """
    }

    // MARK: - Lightroom's preferences

    @Test func `Lightroom's preferences name the catalog it opens at launch, then the ones it opened, escapes and all`() {
        let mac = Self.startupPreferences(
            load: "/Users/ana/Pictures/Lightroom/Lightroom Catalog-v13.lrcat",
            recent: [
                "/Users/ana/Pictures/Lightroom/Lightroom Catalog-v13.lrcat",
                "/Volumes/Archive/Café \"2019\".lrcat",
            ],
        )
        #expect(LightroomPreferences.catalogs(agprefs: Data(mac.utf8)) == [
            "/Users/ana/Pictures/Lightroom/Lightroom Catalog-v13.lrcat", "/Volumes/Archive/Café \"2019\".lrcat",
        ])
        // As Lightroom 6 wrote it on Windows, in a forum post of 2017.
        let windows = #"""
        prefs = {
           RegistrationField_CountryRegion = "4",
           libraryToLoad20 = "K:\\003_Catalogues Lightroom\\WORK\\Work\\Work-LR6.lrcat",
           recentLibraries20 = "recentLibraries = {\
           \"K:\\\\003_Catalogues Lightroom\\\\WORK\\\\Work\\\\Work-LR6.lrcat\",\
           \"E:\\\\RAW\\\\RAW\\\\RAW-LR6.lrcat\",\
        }\
        ",
        }
        """#
        #expect(LightroomPreferences.catalogs(agprefs: Data(windows.utf8)) == [
            #"K:\003_Catalogues Lightroom\WORK\Work\Work-LR6.lrcat"#, #"E:\RAW\RAW\RAW-LR6.lrcat"#,
        ])
        #expect(LightroomPreferences.catalogs(agprefs: Data("prefs = { mylibraryToLoad20 = \"/a.lrcat\" }".utf8)) == [])
        #expect(LightroomPreferences.string(in: Array(#""caf\195\169 \"x\"""#.utf8), at: 0)?.value == "café \"x\"")
        #expect(LightroomPreferences.string(in: Array("\"unfinished\n\"".utf8), at: 0) == nil)
    }

    @Test func `the main preferences, a property list, name catalogs the same way`() throws {
        let home = Home()
        defer { home.remove() }
        let plist = home.locations.home.appending(path: "Library/Preferences/com.adobe.LightroomClassicCC7.plist")
        try home.write(PropertyListSerialization.data(fromPropertyList: [
            "libraryToLoad20": "/Users/ana/Pictures/Lightroom/Lightroom Catalog.lrcat",
            "recentLibraries20": "recentLibraries = {\n\t\"/Users/ana/Work.lrcat\",\n}\n",
        ], format: .binary, options: 0), to: plist)
        #expect(LightroomPreferences.catalogs(in: plist) == [
            "/Users/ana/Pictures/Lightroom/Lightroom Catalog.lrcat", "/Users/ana/Work.lrcat",
        ])
    }

    // MARK: - Finding each part

    @Test func `the catalog Lightroom last used is found, else the newest in Pictures › Lightroom, else none`() throws {
        let home = Home()
        defer { home.remove() }
        let locations = home.locations
        #expect(LightroomSetup.find(locations).catalog == nil)

        let pictures = locations.pictures
        let older = try home.write("older", to: pictures.appending(path: "Lightroom Catalog.lrcat"))
        let newer = try home.write("newer", to: pictures.appending(path: "Lightroom Catalog-v13.lrcat"))
        try home.write("backup", to: pictures.appending(path: "Backups/2026-10-01 0900/Lightroom Catalog-v13.lrcat"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -86400)],
            ofItemAtPath: older.path,
        )
        var found = try #require(LightroomSetup.find(locations).catalog)
        #expect(found.url.lastPathComponent == newer.lastPathComponent && found.source == .pictures)
        #expect(found.size == 5 && found.isOpenInLightroom == false)

        let used = try home.write("used", to: home.base.appending(path: "Elsewhere/Work.lrcat"))
        try home.write(
            Self.startupPreferences(load: #"D:\Catalogs\Work.lrcat"#, recent: [#"D:\Catalogs\Work.lrcat"#, used.path]),
            to: locations.home.appending(
                path: "Library/Application Support/Adobe/Lightroom/Preferences/Lightroom Classic CC 7 Startup Preferences.agprefs",
            ),
        )
        found = try #require(LightroomSetup.find(locations).catalog)
        #expect(found.url.standardizedFileURL == used.standardizedFileURL && found.source == .lastUsed)

        try home.write("", to: LightroomCatalog.lockURL(of: used))
        #expect(LightroomSetup.find(locations).catalog?.isOpenInLightroom == true)
        let lines = LightroomSetupScreen.catalogLines(
            LightroomSetup.find(locations).catalog,
            looking: false,
            status: nil,
        )
        #expect(lines.found == "Work.lrcat, the catalog Lightroom Classic last used" && lines.isProblem)
        #expect(lines.state == "Lightroom Classic has Work.lrcat open: quit Lightroom, or choose a copy of the catalog")
        #expect(LightroomSetupScreen.catalogLines(nil, looking: false, status: nil).found
            == "No catalog found in Lightroom Classic's preferences or in Pictures › Lightroom")
    }

    @Test func `presets are found in Camera Raw's Settings folder, its profiles and photos' sidecars left out`() throws {
        let home = Home()
        defer { home.remove() }
        let locations = home.locations
        var found = LightroomSetup.find(locations)
        #expect(found.presets.isEmpty && found.presetsReadable)
        #expect(LightroomSetupScreen
            .presetsLines(found, nil) == .init(found: "No presets in Camera Raw's Settings folder"))

        let settings = locations.settings
        let warm = try home.write(Self.preset("Warm"), to: settings.appending(path: "Warm.xmp"))
        let cool = try home.write(Self.preset("Cool"), to: settings.appending(path: "Trips/Cool.xmp"))
        try home.write(Self.look("Mine"), to: settings.appending(path: "Profiles/Mine.xmp"))
        try home.write(Self.sidecar, to: settings.appending(path: "IMG_0001.xmp"))
        try home.write("notes", to: settings.appending(path: "Read me.txt"))
        found = LightroomSetup.find(locations)
        #expect(found.presets.map(\.lastPathComponent) == [cool, warm].map(\.lastPathComponent))
        #expect(found.cameraProfiles == [.init(kind: .userCameraRaw, folder: locations.userCameraRaw, count: 1)])
        let lines = LightroomSetupScreen.presetsLines(found, nil)
        #expect(lines.found == "2 presets in Camera Raw's Settings folder" && lines.place == settings.path)
    }

    @Test func `camera profiles are counted where Camera Raw installs them, in the photographer's folder and as chosen`(
    ) throws {
        let home = Home()
        defer { home.remove() }
        var locations = home.locations
        #expect(LightroomSetup.find(locations).cameraProfiles.isEmpty)
        #expect(LightroomSetupScreen.cameraProfileLines(LightroomSetup.find(locations))
            == .init(found: "No Adobe camera profiles on this Mac"))

        let cameraRaw = locations.cameraRaw
        try home.write(
            Self.dcp,
            to: cameraRaw.appending(path: "CameraProfiles/Adobe Standard/Canon EOS R5 Adobe Standard.dcp"),
        )
        try home.write(
            Self.dcp,
            to: cameraRaw.appending(path: "CameraProfiles/Camera/Canon EOS R5/Camera Standard.dcp"),
        )
        try home.write(
            Self.look("Adobe Color"),
            to: cameraRaw.appending(path: "Settings/Adobe/Profiles/Adobe Raw/Color.xmp"),
        )
        var found = LightroomSetup.find(locations)
        #expect(found.cameraProfiles == [.init(kind: .cameraRaw, folder: cameraRaw, count: 3)])
        #expect(LightroomSetupScreen.cameraProfileLines(found).found
            == "3 camera profiles where Lightroom Classic and Camera Raw install them")

        try home.write(Self.dcp, to: locations.userCameraRaw.appending(path: "CameraProfiles/Mine.dcp"))
        let chosen = try home.write(Self.dcp, to: home.base.appending(path: "Chosen/Friend's.dcp"))
        locations.chosenCameraProfiles = [chosen.deletingLastPathComponent()]
        found = LightroomSetup.find(locations)
        #expect(found.cameraProfileCount == 5)
        let lines = LightroomSetupScreen.cameraProfileLines(found)
        #expect(lines.found == "5 camera profiles: 3 where Lightroom Classic and Camera Raw install them, 1 in your "
            + "Camera Raw folder and 1 in the files and folders you chose")
        #expect(lines.place == "\(cameraRaw.path) · \(locations.userCameraRaw.path)" && !lines.isProblem)
        #expect(lines.state.hasPrefix("In use: Redlamp reads them where they are, on this Mac only"))
    }

    @Test func `lens profiles are counted in Camera Raw's folders and in Redlamp's Lens Profiles folder`() throws {
        let home = Home()
        defer { home.remove() }
        let locations = home.locations
        #expect(LightroomSetupScreen.lensProfileLines(LightroomSetup.find(locations))
            == .init(found: "No lens profiles on this Mac"))

        try home.write("<lcp/>", to: locations.lensProfiles.appending(path: "Helios.lcp"))
        var lines = LightroomSetupScreen.lensProfileLines(LightroomSetup.find(locations))
        #expect(lines.found == "1 lens profile in your Lens Profiles folder")
        #expect(lines.state == "In use: Redlamp reads them where they are, on this Mac only.")

        let installed = locations.cameraRaw.appending(path: "LensProfiles/1.0")
        try home.write("<lcp/>", to: installed.appending(path: "Canon/Canon EF 50mm f1.8 STM.lcp"))
        try home.write("<lcp/>", to: installed.appending(path: "Sigma/SIGMA 35mm F1.4 DG HSM A.lcp"))
        try home.write("<lcp/>", to: locations.userCameraRaw.appending(path: "LensProfiles/My lens.lcp"))
        let found = LightroomSetup.find(locations)
        #expect(found.lensProfileCount == 4)
        lines = LightroomSetupScreen.lensProfileLines(found)
        #expect(lines.found == "4 lens profiles: 2 in Camera Raw's lens profiles, 1 in your Camera Raw lens profiles "
            + "and 1 in your Lens Profiles folder")
        #expect(lines.state.hasSuffix("Edits from process 17 on use those in Camera Raw's folders too."))
    }

    @Test func `a folder that can't be read is said to be unreadable, not empty`() throws {
        let home = Home()
        defer { home.remove() }
        let locations = home.locations
        let installed = locations.cameraRaw.appending(path: "LensProfiles/1.0", directoryHint: .isDirectory)
        try home.write("<lcp/>", to: installed.appending(path: "Canon/Lens.lcp"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: installed.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path) }
        let found = LightroomSetup.find(locations)
        #expect(found.lensProfiles == [.init(kind: .cameraRaw, folder: installed, count: 0, isReadable: false)])
        let lines = LightroomSetupScreen.lensProfileLines(found)
        #expect(lines.found == "No lens profiles on this Mac" && lines.isProblem)
        #expect(lines.state == "Redlamp can't read \(installed.path)")
    }

    // MARK: - The window

    @Test func `the window opens on what it found, imports the presets as recipes and goes on to the catalog's report`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let home = Home()
        defer { home.remove() }
        try sandbox.photos(["A.jpg"])
        let other = sandbox.base.appending(path: "Other", directoryHint: .isDirectory)
        try sandbox.photos(["Day/B.jpg"], under: other, from: 1)
        let locations = home.locations
        let catalog = locations.pictures.appending(path: "Lightroom Catalog.lrcat")
        try LightroomWindowTests.catalog(root: sandbox.root, other: other, at: catalog)
        try home.write(Self.preset("Setup warm"), to: locations.settings.appending(path: "Setup warm.xmp"))
        try home.write(Self.preset("Setup cool"), to: locations.settings.appending(path: "Setup cool.xmp"))
        try home.write("<lcp/>", to: locations.lensProfiles.appending(path: "Helios.lcp"))
        let model = try await editor(in: sandbox)
        LightroomWindowController.setupLocations = locations
        defer { LightroomWindowController.setupLocations = nil }

        LightroomWindowController.show(editor: model)
        let window = try #require(LightroomWindowController.current)
        defer { window.close() }
        #expect(window.isShowingSetup)
        try await sandbox.eventually { window.setupFound != nil }
        #expect(window.setupFound?.catalog?.url.lastPathComponent == "Lightroom Catalog.lrcat")
        #expect(window.setupLine("lightroom.setup.catalog.found")?
            .text == "Lightroom Catalog.lrcat, in Pictures › Lightroom")
        #expect(window.setupLine("lightroom.setup.presets.found")?.text == "2 presets in Camera Raw's Settings folder")
        #expect(window.setupLine("lightroom.setup.camera-profiles.found")?
            .text == "No Adobe camera profiles on this Mac")
        #expect(window.setupLine("lightroom.setup.camera-profiles.place")?.shown == false, "nothing found is one line")
        #expect(window.setupLine("lightroom.setup.lens-profiles.found")?.text
            == "1 lens profile in your Lens Profiles folder")
        #expect(window.button("lightroom.import")?.shown == false, "the catalog's screen waits")
        #expect(window.button("lightroom.setup.camera-profiles.choose")?.title == "Choose Camera Profiles…")

        try #require(button("lightroom.setup.presets.import", in: window)).performClick(nil)
        try await sandbox.eventually { window.presetsImported != nil }
        #expect(window.presetsImported?.headline == "Imported 2 Lightroom presets")
        let names = Set(model.recipes.all.filter { $0.group == "Lightroom" }.map(\.name))
        #expect(names.isSuperset(of: ["Setup warm", "Setup cool"]))
        #expect(window.setupLine("lightroom.setup.presets.state")?.text
            == "Imported 2 Lightroom presets. In the Recipes panel under Lightroom.")
        #expect(window.button("lightroom.setup.presets.import")?.title == "Import Again")
        let sheet = try #require(window.window?.attachedSheet, "the presets' report shows over the window")
        window.window?.endSheet(sheet)

        try #require(button("lightroom.setup.catalog.import", in: window)).performClick(nil)
        #expect(!window.isShowingSetup)
        try await sandbox.eventually { window.isReported }
        #expect(window.report?.roots.map(\.state) == [.inLibrary, .notInLibrary])
        #expect(window.button("lightroom.import")?.shown == true && window.button("lightroom.import")?.enabled == true)
        #expect(SidecarStore().load(for: sandbox.photo("A.jpg")) == nil, "going on writes nothing")

        try #require(button("lightroom.back", in: window)).performClick(nil)
        #expect(window.isShowingSetup)
        #expect(window.setupLine("lightroom.setup.catalog.state")?.text
            == "Import… reports what would come across before anything is written. The catalog is read, never changed.")
    }

    @Test func `a catalog chosen on the first screen takes the found one's place until Import… goes on with it`(
    ) async throws {
        let home = Home()
        defer { home.remove() }
        let locations = home.locations
        try home.write("found", to: locations.pictures.appending(path: "Lightroom Catalog.lrcat"))
        let chosen = try home.write("chosen", to: home.base.appending(path: "Copies/Copy.lrcat"))
        let model = EditorModel(engine: StubEngine())
        LightroomWindowController.setupLocations = locations
        defer { LightroomWindowController.setupLocations = nil }
        LightroomWindowController.show(editor: model)
        let window = try #require(LightroomWindowController.current)
        defer { window.close() }
        try await SourcesSandbox.eventually { window.setupFound != nil }
        window.chooseSetupCatalog(chosen)
        #expect(window.setupLine("lightroom.setup.catalog.found")?.text == "Copy.lrcat")
        #expect(window.setupLine("lightroom.setup.catalog.place")?.text
            .hasPrefix(chosen.deletingLastPathComponent().path)
            == true)
        #expect(window.button("lightroom.setup.catalog.import")?.enabled == true)
        #expect(window.button("lightroom.setup.presets.import")?.enabled == false, "no presets were found")
    }

    /// The sandbox's library in an editor whose recipes are kept in the sandbox, not in Application Support.
    private func editor(in sandbox: SourcesSandbox) async throws -> EditorModel {
        let library = FolderLibrary()
        library.add([sandbox.root])
        let service = LibraryService(
            paths: LibraryPaths(root: sandbox.base.appending(path: "Library", directoryHint: .isDirectory)),
            sidecars: library.sidecars,
        ) { url, size in StoreThumbnailMaker.imageIO(url, nil, size) }
        library.attach(service)
        sandbox.closes(service)
        try await SourcesSandbox.eventually { await service.canShow(sandbox.root, includingSubfolders: true) }
        let recipes = sandbox.base.appending(path: "Recipes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recipes, withIntermediateDirectories: true)
        let model = EditorModel(
            engine: StubEngine(),
            recipes: RecipeCatalog(engine: StubEngine(), library: RecipeLibrary(root: recipes, includeBundled: false)),
            library: library,
        )
        model.showModule(.library)
        return model
    }

    private func button(_ identifier: String, in window: LightroomWindowController) -> NSButton? {
        func find(_ view: NSView) -> NSButton? {
            if view.accessibilityIdentifier() == identifier {
                return view as? NSButton
            }
            return view.subviews.lazy.compactMap(find).first
        }
        return window.window?.contentView.flatMap(find)
    }
}
