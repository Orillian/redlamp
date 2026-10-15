import Foundation
import RedlampEngineAPI

/// What Help › Acknowledgements shows (ARC-25): Redlamp's own licence and where its source is,
/// each component built into the app with its licence, the downloadable models' licences, and the
/// trademark notices (`TrademarkNotices`).
///
/// The licence texts are the repository's `LICENSES/`, and `LICENSE` as `Redlamp-MPL-2.0.txt`,
/// copied into the app's `Resources/Acknowledgements`; `AcknowledgementsTests` fails when the
/// copies, this list, the vendored libraries' versions or the resolved packages fall out of step.
public enum Acknowledgements {
    /// A licence text bundled in the app, by its file name in `LICENSES/`.
    public struct LicenceText: Sendable, Hashable, Identifiable {
        public var title: String
        public var file: String

        public var id: String {
            file
        }

        public init(_ title: String, file: String) {
            self.title = title
            self.file = file
        }

        /// The text, from the app's resources; nil if the build left it out.
        public func contents(in bundle: Bundle = .main) -> String? {
            bundle.url(forResource: file, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
    }

    /// A library built into the app.
    public struct Component: Sendable, Hashable, Identifiable {
        public var name: String
        public var version: String
        /// What Redlamp uses it for.
        public var use: String
        public var licence: String
        /// Its source code, at the version built.
        public var source: URL
        /// The source offer, or how its licence applies.
        public var note: String?
        public var texts: [LicenceText]

        public var id: String {
            name
        }
    }

    public static let repository = URL(string: "https://github.com/pdcgomes/redlamp")!

    /// Redlamp's source code at the commit this build was made from, when a release says which.
    public static func source(commit: String?) -> URL {
        guard let commit, !commit.isEmpty else { return repository }
        return repository.appending(path: "tree/\(commit)")
    }

    public static let redlampLicence = LicenceText("Mozilla Public License 2.0", file: "Redlamp-MPL-2.0.txt")

    public static let redlampNotice = """
    Redlamp is open source, under the Mozilla Public License 2.0 (MPL-2.0). You can get its source \
    code, for this version and every other, from its repository on GitHub, and use, change and \
    share it under the licence's terms, which follow.

    Two files of Redlamp's source, its X-Trans demosaic (DemosaicXTrans.metal and \
    XTransDemosaic.swift), are ported from LibRaw and are covered by the CDDL-1.0 instead; LibRaw's \
    entry has that licence.
    """

    public static let libRaw = Component(
        name: "LibRaw", version: "Redlamp's fork, commit 3b20539",
        use: "Reads raw files from cameras.", licence: "CDDL-1.0",
        source: URL(
            string: "https://github.com/pdcgomes/redlamp-libraw/tree/3b20539d3faa766a370e93a529a3b87edffbf0f6",
        )!,
        note: """
        LibRaw is available under the LGPL-2.1 or the CDDL-1.0; Redlamp uses it under the CDDL-1.0. \
        Redlamp's copy is LibRaw with the changes its REDLAMP.md file lists. Its source code, as \
        built into this app, is available from the link below, under the CDDL-1.0.
        """,
        texts: [
            LicenceText("LibRaw's copyright notice", file: "LibRaw-COPYRIGHT.txt"),
            LicenceText("Common Development and Distribution License 1.0", file: "CDDL-1.0.txt"),
        ],
    )

    public static let libjxl = Component(
        name: "libjxl", version: "0.12.0", use: "Writes JPEG XL exports.",
        licence: "BSD-3-Clause, with Google's patent grant",
        source: URL(string: "https://github.com/libjxl/libjxl/tree/v0.12.0")!, note: nil,
        texts: [
            LicenceText("BSD 3-Clause License", file: "libjxl-BSD-3-Clause.txt"),
            LicenceText("Additional IP Rights Grant (Patents)", file: "libjxl-PATENTS.txt"),
        ],
    )

    public static let highway = Component(
        name: "Highway", version: "commit 457c891", use: "Vector code in libjxl.", licence: "BSD-3-Clause",
        source: URL(string: "https://github.com/google/highway/tree/457c891775a7397bdb0376bb1031e6e027af1c48")!,
        note: "Highway is available under the Apache-2.0 or the BSD-3-Clause; Redlamp uses it under the BSD-3-Clause.",
        texts: [LicenceText("BSD 3-Clause License", file: "highway-BSD-3-Clause.txt")],
    )

    public static let brotli = Component(
        name: "Brotli", version: "commit 028fb5a", use: "Compression in libjxl.", licence: "MIT",
        source: URL(string: "https://github.com/google/brotli/tree/028fb5a23661f123017c060daa546b55cf4bde29")!,
        note: nil, texts: [LicenceText("MIT License", file: "brotli-MIT.txt")],
    )

    public static let skcms = Component(
        name: "skcms", version: "commit 96d9171", use: "Colour profiles in libjxl.", licence: "BSD-3-Clause",
        source: URL(string: "https://github.com/google/skcms/tree/96d9171c94b937a1b5f0293de7309ac16311b722")!,
        note: nil, texts: [LicenceText("BSD 3-Clause License", file: "skcms-BSD-3-Clause.txt")],
    )

    public static let mlxSwift = Component(
        name: "MLX Swift", version: "0.32.3", use: "Runs Generative Remove's model on this Mac.", licence: "MIT",
        source: URL(string: "https://github.com/ml-explore/mlx-swift/tree/0.32.3")!,
        note: """
        MLX Swift includes MLX and MLX C (MIT), metal-cpp (Apache-2.0), {fmt} (MIT), JSON for Modern \
        C++ (MIT) and PocketFFT (BSD-3-Clause), each with its licence below.
        """,
        texts: [
            LicenceText("MLX Swift", file: "mlx-swift-MIT.txt"),
            LicenceText("MLX", file: "mlx-MIT.txt"),
            LicenceText("MLX C", file: "mlx-c-MIT.txt"),
            LicenceText("metal-cpp", file: "metal-cpp-Apache-2.0.txt"),
            LicenceText("{fmt}", file: "fmt-MIT.txt"),
            LicenceText("JSON for Modern C++", file: "nlohmann-json-MIT.txt"),
            LicenceText("PocketFFT", file: "pocketfft-BSD-3-Clause.txt"),
        ],
    )

    public static let swiftNumerics = Component(
        name: "Swift Numerics", version: "1.1.1", use: "Complex numbers for MLX Swift.",
        licence: "Apache-2.0, with the Runtime Library Exception",
        source: URL(string: "https://github.com/apple/swift-numerics/tree/1.1.1")!, note: nil,
        texts: [LicenceText("Apache License 2.0", file: "swift-numerics-Apache-2.0.txt")],
    )

    public static let sparkle = Component(
        name: "Sparkle", version: "2.10.0", use: "Checks for updates and installs them.", licence: "MIT",
        source: URL(string: "https://github.com/sparkle-project/Sparkle/tree/2.10.0")!,
        note: "Sparkle's licence includes those of bsdiff, sais-lite, Ed25519 and SUSignatureVerifier, which it uses.",
        texts: [LicenceText("MIT License, and the licences it includes", file: "Sparkle-MIT.txt")],
    )

    /// The components this build is made with: the App Store build has no Sparkle, since the App
    /// Store updates it.
    public static let components: [Component] = {
        var all = [libRaw, libjxl, highway, brotli, skcms, mlxSwift, swiftNumerics]
        #if !REDLAMP_APP_STORE
            all.append(sparkle)
        #endif
        return all
    }()

    /// The page a licence's standard text is on, for a model whose download brings no copy of it.
    public static func standardText(of licence: String) -> URL? {
        switch licence {
        case "Apache-2.0": URL(string: "https://www.apache.org/licenses/LICENSE-2.0")
        case "MIT": URL(string: "https://opensource.org/license/mit")
        default: nil
        }
    }
}

/// How a downloadable model's licence is shown: the copy that came with the download, a link to
/// the copy its publisher serves with the files, or, for a model whose files carry none, the
/// licence's name with links to the model's page and the licence's standard text.
public enum ModelLicence: Equatable {
    case downloaded(URL)
    case withDownload(URL)
    case byName(page: URL?, standard: URL?)

    public init(_ model: ModelInfo) {
        if let file = model.licenceFile, FileManager.default.fileExists(atPath: file.path) {
            self = .downloaded(file)
        } else if let url = model.licenceURL {
            self = .withDownload(url)
        } else {
            self = .byName(page: model.page, standard: model.licence.flatMap(Acknowledgements.standardText))
        }
    }

    /// "Weights: Apache-2.0. Code: MIT." when they differ, else the one licence.
    public static func summary(_ model: ModelInfo) -> String {
        let weights = model.licence ?? "Not stated"
        guard let code = model.codeLicence, code != weights else { return weights }
        return "Weights: \(weights). Code: \(code)."
    }
}
