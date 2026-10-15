import Foundation
import RedlampEngineAPI
import RedlampRecipes
import Testing
@testable import RedlampUI

/// Help › Acknowledgements (ARC-25) stays in step with what the app is made of: the licence texts
/// in `LICENSES/`, their copies in the app's resources, the vendored libraries and the resolved
/// packages, and the third-party names the app shows.
struct AcknowledgementsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../..").standardizedFileURL
    static let licences = root.appending(path: "LICENSES")
    static let bundled = root.appending(path: "apps/RedlampMac/Resources/Acknowledgements")
    static let checkouts = root.appending(path: "Tuist/.build/checkouts")

    /// Every component, the direct download's Sparkle included.
    static let everyComponent = [
        Acknowledgements.libRaw, Acknowledgements.libjxl, Acknowledgements.highway, Acknowledgements.brotli,
        Acknowledgements.skcms, Acknowledgements.mlxSwift, Acknowledgements.swiftNumerics, Acknowledgements.sparkle,
    ]

    static func files(in folder: URL) -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") })
    }

    @Test func `the app bundles every licence in LICENSES unchanged, and Redlamp's own`() throws {
        let licences = Self.files(in: Self.licences)
        #expect(!licences.isEmpty)
        #expect(Self.files(in: Self.bundled) == licences.union(["Redlamp-MPL-2.0.txt"]))
        for file in licences {
            let original = try Data(contentsOf: Self.licences.appending(path: file))
            let copy = try? Data(contentsOf: Self.bundled.appending(path: file))
            #expect(copy == original, "Copy LICENSES/\(file) into apps/RedlampMac/Resources/Acknowledgements")
        }
        let mpl = try Data(contentsOf: Self.root.appending(path: "LICENSE"))
        #expect(try Data(contentsOf: Self.bundled.appending(path: "Redlamp-MPL-2.0.txt")) == mpl)
    }

    @Test func `the window shows every bundled licence, and only those`() {
        let shown = Set(([Acknowledgements.redlampLicence] + Self.everyComponent.flatMap(\.texts)).map(\.file))
        #expect(shown == Self.files(in: Self.bundled))
    }

    @Test func `each vendored library is acknowledged at the version that's built, from its source`() throws {
        struct Library: Decodable {
            var version: String
            var url: String
        }
        let config = try JSONDecoder().decode(
            [String: Library].self, from: Data(contentsOf: Self.root.appending(path: "config/vendored-libs.json")),
        )
        let components: [String: Acknowledgements.Component] = [
            "LibRaw": Acknowledgements.libRaw, "libjxl": Acknowledgements.libjxl, "highway": Acknowledgements.highway,
            "brotli": Acknowledgements.brotli, "skcms": Acknowledgements.skcms,
        ]
        #expect(Set(config.keys) == Set(components.keys))
        for (name, library) in config {
            let component = try #require(components[name], "\(name) isn't acknowledged")
            let source = component.source.absoluteString
            #expect(source.contains(library.version), "\(name)'s source isn't at \(library.version)")
            #expect(component.version.contains(library.version.prefix(7)), "\(name) says \(component.version)")
            let repository = library.url.components(separatedBy: "/archive/").first ?? library.url
            #expect(source.hasPrefix("\(repository)/tree/"), "\(name)'s source isn't \(repository)")
        }
    }

    @Test func `each resolved Swift package is acknowledged at its version`() throws {
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable {
                    var version: String
                }

                var identity: String
                var location: String
                var state: State
            }

            var pins: [Pin]
        }
        let resolved = try JSONDecoder().decode(
            Resolved.self, from: Data(contentsOf: Self.root.appending(path: "Tuist/Package.resolved")),
        )
        let components: [String: Acknowledgements.Component] = [
            "mlx-swift": Acknowledgements.mlxSwift, "sparkle": Acknowledgements.sparkle,
            "swift-numerics": Acknowledgements.swiftNumerics,
        ]
        #expect(Set(resolved.pins.map(\.identity)) == Set(components.keys))
        for pin in resolved.pins {
            let component = try #require(components[pin.identity], "\(pin.identity) isn't acknowledged")
            #expect(component.source.absoluteString == "\(pin.location)/tree/\(pin.state.version)")
            #expect(component.version == pin.state.version)
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: AcknowledgementsTests.checkouts.path)))
    func `the packages' licences are the ones in their checkouts`() throws {
        let cmlx = "mlx-swift/Source/Cmlx"
        let copies = [
            "Sparkle-MIT.txt": "Sparkle/LICENSE",
            "mlx-swift-MIT.txt": "mlx-swift/LICENSE",
            "mlx-MIT.txt": "\(cmlx)/mlx/LICENSE",
            "mlx-c-MIT.txt": "\(cmlx)/mlx-c/LICENSE",
            "metal-cpp-Apache-2.0.txt": "\(cmlx)/metal-cpp/LICENSE.txt",
            "fmt-MIT.txt": "\(cmlx)/fmt/LICENSE",
            "nlohmann-json-MIT.txt": "\(cmlx)/json/LICENSE.MIT",
            "swift-numerics-Apache-2.0.txt": "swift-numerics/LICENSE.txt",
        ]
        for (file, original) in copies {
            let checkout = try Data(contentsOf: Self.checkouts.appending(path: original))
            #expect(try Data(contentsOf: Self.licences.appending(path: file)) == checkout, "\(file) isn't \(original)")
        }
        let pocketFFT = try String(
            contentsOf: Self.checkouts.appending(path: "\(cmlx)/mlx/mlx/3rdparty/pocketfft.h"), encoding: .utf8,
        )
        let notice = try String(
            contentsOf: Self.licences.appending(path: "pocketfft-BSD-3-Clause.txt"), encoding: .utf8,
        )
        #expect(pocketFFT.contains(notice), "pocketfft-BSD-3-Clause.txt isn't the notice at the top of pocketfft.h")
    }

    @Test func `Sparkle is acknowledged only in the direct download`() {
        #if REDLAMP_APP_STORE
            #expect(!Acknowledgements.components.contains(Acknowledgements.sparkle))
        #else
            #expect(Acknowledgements.components.contains(Acknowledgements.sparkle))
        #endif
        #expect(Acknowledgements.components.count >= 7)
    }

    @Test func `Redlamp's source offer points at the commit a release is built from`() {
        #expect(
            Acknowledgements.source(commit: "d7ce969").absoluteString
                == "https://github.com/pdcgomes/redlamp/tree/d7ce969",
        )
        #expect(Acknowledgements.source(commit: "") == Acknowledgements.repository)
        #expect(Acknowledgements.source(commit: nil).absoluteString == "https://github.com/pdcgomes/redlamp")
    }

    // MARK: - Models

    private func model(licence: String?, url: URL? = nil, file: URL? = nil, code: String? = nil) -> ModelInfo {
        ModelInfo(
            id: "m", name: "Model", purpose: "Tests", downloadBytes: 1, state: .notDownloaded, licence: licence,
            licenceURL: url, codeLicence: code ?? licence,
            page: URL(string: "https://huggingface.co/apple/coreml-sam2.1-tiny"), licenceFile: file,
        )
    }

    @Test func `a model whose files carry no licence shows its licence by name, with its page`() {
        #expect(ModelLicence(model(licence: "Apache-2.0")) == .byName(
            page: URL(string: "https://huggingface.co/apple/coreml-sam2.1-tiny"),
            standard: URL(string: "https://www.apache.org/licenses/LICENSE-2.0"),
        ))
        #expect(ModelLicence(model(licence: "SAM License")) == .byName(
            page: URL(string: "https://huggingface.co/apple/coreml-sam2.1-tiny"), standard: nil,
        ))
    }

    @Test func `a model with a licence file shows the copy it downloaded, or links to it until then`() throws {
        let remote = try #require(URL(string: "https://github.com/pdcgomes/redlamp/releases/download/m/LICENSE.txt"))
        let local = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-LICENSE.txt")
        #expect(ModelLicence(model(licence: "MIT", url: remote, file: local)) == .withDownload(remote))
        try Data("MIT License".utf8).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        #expect(ModelLicence(model(licence: "MIT", url: remote, file: local)) == .downloaded(local))
    }

    @Test func `a model's code and weights licences are both named when they differ`() {
        #expect(ModelLicence.summary(model(licence: "Apache-2.0", code: "MIT")) == "Weights: Apache-2.0. Code: MIT.")
        #expect(ModelLicence.summary(model(licence: "Apache-2.0")) == "Apache-2.0")
    }

    // MARK: - Trademarks

    @Test func `a notice names the owner and says Redlamp isn't affiliated with or endorsed by them`() {
        #expect(TrademarkNotices.notice(naming: "Lightroom")?.text == """
        Adobe, Lightroom, Lightroom Classic, Adobe Bridge, Camera Raw and Photoshop are trademarks of \
        Adobe Inc. Redlamp isn't affiliated with or endorsed by Adobe.
        """)
        #expect(TrademarkNotices.notice(naming: "Photo Mechanic")?.text == """
        Photo Mechanic is a trademark of Camera Bits, Inc. Redlamp isn't affiliated with or endorsed by Camera Bits.
        """)
        let marks = TrademarkNotices.all.flatMap(\.marks).map { $0.lowercased() }
        #expect(Set(marks).count == marks.count, "A name is in two notices")
    }

    @Test func `every film look's maker and stock has a notice`() throws {
        for look in FilmLookCatalog.looks {
            let makers = look.maker.components(separatedBy: " · ")
            for maker in makers {
                #expect(TrademarkNotices.notice(naming: maker)?.kind == .film, "No film notice names \(maker)")
            }
            let notice = try #require(TrademarkNotices.notice(naming: makers[0]))
            #expect(
                notice.marks.contains { look.name.hasPrefix($0) },
                "\(look.name) begins with none of the names in \(notice.owner)'s notice",
            )
        }
    }

    @Test func `every keymap preset names an app with a notice`() {
        for preset in KeymapPreset.allCases {
            #expect(TrademarkNotices.notice(naming: preset.title)?.kind == .apps, "No notice names \(preset.title)")
        }
    }

    @Test func `every camera log names a maker and a curve that have a notice`() {
        for space in CameraLogSpace.allCases {
            let notice = TrademarkNotices.all.first { $0.marks.contains { space.name.hasPrefix("\($0) ") } }
            let named = notice?.marks.filter { space.name.contains($0) } ?? []
            #expect(named.count >= 2, "\(space.name) needs its maker and its curve in a notice")
        }
    }

    #if !REDLAMP_APP_STORE
        @Test func `the firmware model's own simulations have Fujifilm's notice`() {
            for simulation in FirmwareSimulation.allCases where simulation.slot == nil {
                let name = simulation.name.components(separatedBy: " + ")[0]
                #expect(TrademarkNotices.notice(naming: name)?.shortOwner == "Fujifilm", "No notice names \(name)")
            }
        }
    #endif
}
