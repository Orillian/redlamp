import CryptoKit
import Foundation
import Testing
@testable import RedlampRecipes

/// A model of one simulation whose stages are identities, so tests can seal, host and open a
/// model on any Mac without the model folder. None of its numbers come from the folder.
enum SyntheticFirmwareModel {
    static let files = FirmwareFilmModel.Files(
        parameters: Data("""
        {"Synthetic": {"matrix": [1, 0, 0, 0, 1, 0, 0, 0, 1], "hdr": [0], "curves": [[0, 1], [0, 1], [0, 1]],
          "chroma": [[1, 0], [0, 1]]}}
        """.utf8),
        toneGains: Data(#"{"Synthetic": {"0": {"H": {"0": [1, 1]}, "S": {"0": [1, 1]}}}}"#.utf8),
        calibration: Data(
            #"{"pre_matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "chroma_scale": [1, 1], "chroma_swap": false, "gamut": false}"#
                .utf8,
        ),
        constants: Data("""
        {"bins_per_stop": 1, "exposure_k": 1, "gain_unit": 1, "gain_clip_bin": 0, "tone_key_neutral": 0,
         "tone_key_steps_per_unit": 1, "dr_index": {"100": 0}, "luma_weights": [0.25, 0.5, 0.25],
         "luma_floor": 0.5, "matrix_unit": 1, "knot_intervals_per_header": 1, "curve_input_max": 1,
         "curve_output_max": 1, "ycbcr_matrix": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "chroma_unit": 1,
         "color_factor": {"0": 1}, "color_factor_unit": 1, "toning_per_step": {"wc": [0, 0], "mg": [0, 0]},
         "toning_unit": 1, "toning_taper_luma_scale": 1, "toning_taper_y": [0, 1], "toning_taper_w": [1, 1],
         "sepia_unit": 1}
        """.utf8),
    )

    static let secret = SymmetricKey(data: Data((0 ..< 32).map { UInt8($0) }))
    static let team = "3JP75Z3F98"
    static var innerKey: SymmetricKey {
        FirmwareModelKey.innerKey(secret: secret, teamIdentifier: team)
    }

    /// The four files written to a new folder, as a model folder holds them.
    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "firmware-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let contents = [files.parameters, files.toneGains, files.calibration, files.constants]
        for (name, data) in zip(FirmwareFilmModel.fileNames, contents) {
            try data.write(to: folder.appending(path: name))
        }
        return folder
    }
}

private func hex(_ key: SymmetricKey) -> String {
    key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
}

private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

/// The hosted file's format and keys (TON-50), on the synthetic model.
struct FirmwareModelPackTests {
    private let outerKey = SymmetricKey(size: .bits256)

    private func same(_ a: FirmwareFilmModel.Files, _ b: FirmwareFilmModel.Files) -> Bool {
        a.parameters == b.parameters && a.toneGains == b.toneGains && a.calibration == b.calibration
            && a.constants == b.constants
    }

    @Test func `a pack opens to its four files under the keys it was sealed with`() throws {
        let files = SyntheticFirmwareModel.files
        let sealed = try FirmwareModelPack.seal(files, innerKey: SyntheticFirmwareModel.innerKey, outerKey: outerKey)
        let opened = try FirmwareModelPack.open(sealed, outerKey: outerKey, innerKey: SyntheticFirmwareModel.innerKey)
        #expect(same(opened, files))
    }

    @Test func `the hosted key alone opens only to the inner seal`() throws {
        let files = SyntheticFirmwareModel.files
        let sealed = try FirmwareModelPack.seal(files, innerKey: SyntheticFirmwareModel.innerKey, outerKey: outerKey)
        let inner = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: outerKey)
        for plaintext in [files.parameters, files.toneGains, files.calibration, files.constants] {
            #expect(inner.firstRange(of: plaintext) == nil)
        }
        #expect(inner.firstRange(of: Data("Synthetic".utf8)) == nil)
        let reSigned = FirmwareModelKey.innerKey(secret: SyntheticFirmwareModel.secret, teamIdentifier: "ABCDE12345")
        #expect(throws: FirmwareModelPack.PackError.innerSeal) {
            try FirmwareModelPack.open(sealed, outerKey: outerKey, innerKey: reSigned)
        }
    }

    @Test func `a pack doesn't open with another hosted key`() throws {
        let sealed = try FirmwareModelPack.seal(
            SyntheticFirmwareModel.files, innerKey: SyntheticFirmwareModel.innerKey, outerKey: outerKey,
        )
        #expect(throws: FirmwareModelPack.PackError.outerSeal) {
            try FirmwareModelPack.open(
                sealed, outerKey: SymmetricKey(size: .bits256), innerKey: SyntheticFirmwareModel.innerKey,
            )
        }
    }

    @Test func `a damaged pack doesn't open`() throws {
        var sealed = try FirmwareModelPack.seal(
            SyntheticFirmwareModel.files, innerKey: SyntheticFirmwareModel.innerKey, outerKey: outerKey,
        )
        sealed[sealed.count / 2] ^= 0x01
        #expect(throws: FirmwareModelPack.PackError.outerSeal) {
            try FirmwareModelPack.open(sealed, outerKey: outerKey, innerKey: SyntheticFirmwareModel.innerKey)
        }
    }

    @Test func `the inner key's derivation is pinned, so installed releases keep opening the file`() {
        // Computed with Python's hmac and hashlib (RFC 5869), not with CryptoKit.
        #expect(hex(FirmwareModelKey.salt) == "9b1c7f30e2a4586dc10a3ed7058a61f92b940e77bc6a0fc853b219e5478d")
        #expect(hex(SyntheticFirmwareModel.innerKey) ==
            "fb7dae2a9ebb8bc5fdac379c1400134db50d08ac9fa7bb8158fba20b4feb6575")
        let other = FirmwareModelKey.innerKey(secret: SyntheticFirmwareModel.secret, teamIdentifier: "ABCDE12345")
        #expect(hex(other) == "784633b8d7298c0555c6178654787b1231d1a37b38b8f3da48c58318eab5b0e8")
    }

    @Test func `the secret's mask is pinned, and unmasking gives the secret back`() throws {
        let masked = FirmwareModelKey.masked(secret: SyntheticFirmwareModel.secret)
        #expect(hex(masked) == "a743dc1a58f6882c78cf1b96ab4fd0164ce29c3864d3078abf5bc40240ee9034")
        let unmasked = try #require(FirmwareModelKey.secret(fromMasked: masked))
        #expect(hex(unmasked) == hex(SyntheticFirmwareModel.secret))
        #expect(FirmwareModelKey.secret(fromMasked: []) == nil)
        #expect(FirmwareModelKey.secret(fromMasked: Array(masked.prefix(16))) == nil)
    }

    @Test func `a build from source carries no secret`() {
        #expect(FirmwareBakedSecret.masked.isEmpty && FirmwareModelKey.bakedSecret == nil)
    }

    @Test func `a model opened from a pack renders as the one read from its folder`() throws {
        let sealed = try FirmwareModelPack.seal(
            SyntheticFirmwareModel.files, innerKey: SyntheticFirmwareModel.innerKey, outerKey: outerKey,
        )
        let hosted = try FirmwareFilmModel(
            sealed: sealed,
            outerKey: outerKey,
            innerKey: SyntheticFirmwareModel.innerKey,
        )
        let folder = try FirmwareFilmModel(folder: SyntheticFirmwareModel.folder())
        #expect(hosted.simulationNames == ["Synthetic"] && hosted.source.hasPrefix("hosted:"))
        for input in [SIMD3(0.1, 0.2, 0.3), SIMD3(0.5, 0.5, 0.5), SIMD3(2.0, 0.0, 0.7)] {
            #expect(try hosted.render(input, "Synthetic") == folder.render(input, "Synthetic"))
        }
    }
}

/// The hosted file as the app fetches, keeps and withdraws it, with file URLs for the website.
struct FirmwareModelHostTests {
    private let outerKey = SymmetricKey(size: .bits256)
    private let site = FileManager.default.temporaryDirectory.appending(path: "firmware-site-\(UUID().uuidString)")

    private func publish() throws -> FirmwareModelHost.Addresses {
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        let sealed = try FirmwareModelPack.seal(
            SyntheticFirmwareModel.files, innerKey: SyntheticFirmwareModel.innerKey, outerKey: outerKey,
        )
        try sealed.write(to: site.appending(path: "a"))
        try outerKey.withUnsafeBytes { Data($0) }.write(to: site.appending(path: "b"))
        return FirmwareModelHost.Addresses(tables: site.appending(path: "a"), key: site.appending(path: "b"))
    }

    private func makeHost(
        _ addresses: FirmwareModelHost.Addresses, innerKey: SymmetricKey? = SyntheticFirmwareModel.innerKey,
    ) -> FirmwareModelHost {
        FirmwareModelHost(
            addresses: addresses, keptFile: site.appending(path: "kept/tables.bin"), timeout: 5,
            innerKey: { innerKey },
        )
    }

    @Test func `the model opens from the hosted file, which is kept here sealed`() async throws {
        let model = try await makeHost(publish()).open().get()
        #expect(model.simulationNames == ["Synthetic"])
        let kept = try Data(contentsOf: site.appending(path: "kept/tables.bin"))
        #expect(try kept == Data(contentsOf: site.appending(path: "a")))
        #expect(kept.firstRange(of: SyntheticFirmwareModel.files.constants) == nil)
    }

    @Test func `deleting the hosted file turns the model off and deletes the kept copy`() async throws {
        let addresses = try publish()
        _ = try await makeHost(addresses).open().get()
        try FileManager.default.removeItem(at: addresses.tables)
        #expect(await makeHost(addresses).open() == .failure(.withdrawn))
        #expect(!FileManager.default.fileExists(atPath: site.appending(path: "kept/tables.bin").path))
    }

    @Test func `deleting the hosted key turns the model off`() async throws {
        let addresses = try publish()
        _ = try await makeHost(addresses).open().get()
        try FileManager.default.removeItem(at: addresses.key)
        #expect(await makeHost(addresses).open() == .failure(.withdrawn))
    }

    @Test func `a changed key turns the model off`() async throws {
        let addresses = try publish()
        try SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.write(to: addresses.key)
        #expect(await makeHost(addresses).open() == .failure(.unopenable))
    }

    @Test func `a build that can't derive the inner key doesn't open it`() async throws {
        let addresses = try publish()
        #expect(await makeHost(addresses, innerKey: nil).open() == .failure(.notThisBuild))
    }

    @Test func `the kept copy opens while the hosted file can't be fetched`() async throws {
        let addresses = try publish()
        _ = try await makeHost(addresses).open().get()
        // A folder where the file was: it exists, so it isn't withdrawn, but it can't be read.
        try FileManager.default.removeItem(at: addresses.tables)
        try FileManager.default.createDirectory(at: addresses.tables, withIntermediateDirectories: false)
        #expect(try await makeHost(addresses).open().get().simulationNames == ["Synthetic"])
    }

    @Test func `a build from source carries no addresses`() {
        #expect(FirmwareModelHost.Addresses(bundle: .main) == nil)
    }

    @Test func `the model comes from the folder when it holds the files, else from the hosted file`() throws {
        let suite = "firmware-source-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FirmwareFilmModel.source(defaults) == nil)
        defaults.set(true, forKey: FirmwareFilmModel.enabledKey)
        let folder = try SyntheticFirmwareModel.folder()
        defaults.set(folder.path, forKey: FirmwareFilmModel.folderKey)
        guard case let .folder(found)? = FirmwareFilmModel.source(defaults) else {
            Issue.record("the folder holds the files")
            return
        }
        #expect(found.standardizedFileURL.path == folder.standardizedFileURL.path)
        defaults.set(site.appending(path: "empty").path, forKey: FirmwareFilmModel.folderKey)
        #expect(FirmwareFilmModel.source(defaults) == .unavailable)
    }

    @Test func `the signing identity is a Team ID or none`() {
        let team = FirmwareSigningIdentity.current()
        #expect(team == nil || team?.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil)
    }
}

/// `FirmwareModelPacking`, the CLI's way in, on the synthetic model.
struct FirmwareModelPackingTests {
    @Test func `a reseal under the kept secret opens with the key releases already derive`() throws {
        let folder = try SyntheticFirmwareModel.folder()
        let first = try FirmwareModelPacking.sealWithNewSecret(modelFolder: folder, team: SyntheticFirmwareModel.team)
        let again = try FirmwareModelPacking.reseal(
            modelFolder: folder, team: SyntheticFirmwareModel.team, maskedSecret: first.maskedSecret,
        )
        #expect(again.maskedSecret == first.maskedSecret && again.outerKey != first.outerKey)
        let released = try #require(FirmwareModelKey.secret(fromMasked: first.maskedSecret))
        let innerKey = FirmwareModelKey.innerKey(secret: released, teamIdentifier: SyntheticFirmwareModel.team)
        let model = try FirmwareFilmModel(
            sealed: again.sealed,
            outerKey: SymmetricKey(data: again.outerKey),
            innerKey: innerKey,
        )
        #expect(model.simulationNames == ["Synthetic"] && again.simulationCount == 1)
    }

    @Test func `the check opens hosted files only with the kept secret and team they were sealed for`() throws {
        let folder = try SyntheticFirmwareModel.folder()
        let output = try FirmwareModelPacking.sealWithNewSecret(modelFolder: folder, team: SyntheticFirmwareModel.team)
        #expect(try FirmwareModelPacking.check(
            sealed: output.sealed, outerKey: output.outerKey, team: SyntheticFirmwareModel.team,
            maskedSecret: output.maskedSecret,
        ) == 1)
        let other = try FirmwareModelPacking.sealWithNewSecret(modelFolder: folder, team: SyntheticFirmwareModel.team)
        #expect(throws: FirmwareModelPack.PackError.innerSeal) {
            try FirmwareModelPacking.check(
                sealed: output.sealed, outerKey: output.outerKey, team: SyntheticFirmwareModel.team,
                maskedSecret: other.maskedSecret,
            )
        }
        #expect(throws: FirmwareModelPack.PackError.innerSeal) {
            try FirmwareModelPacking.check(
                sealed: output.sealed, outerKey: output.outerKey, team: "ABCDE12345", maskedSecret: output.maskedSecret,
            )
        }
    }

    @Test func `packing refuses a team that isn't a Team ID and a secret of the wrong length`() throws {
        let folder = try SyntheticFirmwareModel.folder()
        #expect(throws: (any Error).self) {
            try FirmwareModelPacking.sealWithNewSecret(modelFolder: folder, team: "not-a-team")
        }
        #expect(throws: (any Error).self) {
            try FirmwareModelPacking.reseal(
                modelFolder: folder,
                team: SyntheticFirmwareModel.team,
                maskedSecret: [1, 2],
            )
        }
    }
}

/// The real model through its pack, on a Mac with the model folder; skipped elsewhere.
@Suite(.enabled(if: FirmwareTestModel.isAvailable))
struct FirmwareModelPackFolderTests {
    @Test func `the model folder's files seal and open to a model that renders as the folder's`() throws {
        let folder = try FirmwareTestModel.model()
        let outerKey = SymmetricKey(size: .bits256)
        let sealed = try FirmwareModelPack.seal(
            FirmwareFilmModel.Files(folder: FirmwareTestModel.folder), innerKey: SyntheticFirmwareModel.innerKey,
            outerKey: outerKey,
        )
        let hosted = try FirmwareFilmModel(
            sealed: sealed,
            outerKey: outerKey,
            innerKey: SyntheticFirmwareModel.innerKey,
        )
        #expect(hosted.simulationNames == folder.simulationNames)
        for name in folder.simulationNames {
            for input in [SIMD3(0.02, 0.05, 0.1), SIMD3(0.18, 0.18, 0.18), SIMD3(0.9, 0.4, 0.2)] {
                #expect(try hosted.render(input, name, highlight: 1, shadow: -1) == folder.render(
                    input, name, highlight: 1, shadow: -1,
                ))
            }
        }
    }
}

extension Result where Success == FirmwareFilmModel, Failure == FirmwareModelHost.Failure {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.failure(a), .failure(b)): a == b
        default: false
        }
    }
}
