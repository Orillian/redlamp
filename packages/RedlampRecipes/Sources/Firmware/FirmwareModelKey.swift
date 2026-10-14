import CryptoKit
import Foundation

/// The firmware model's inner key (TON-50): the layer under the hosted outer key. It is derived,
/// never a literal, from three inputs, so the hosted file can't be opened by holding the public
/// repository and a release binary's Team ID alone:
///
/// - a secret release builds carry masked in the binary (`FirmwareBakedSecret`), absent from the
///   sources and from builds from source; it never changes, since installed releases need it;
/// - the Team ID of the running app's valid signature (`FirmwareSigningIdentity`), so a patched or
///   re-signed copy derives a different key and can't open the file;
/// - three salt pieces spread across the Firmware sources (`FirmwareKeySaltA`, `B`, `C`), public
///   but kept apart so no single file holds the salt.
///
/// Without the secret the other two are public, so the key could be computed offline; with it,
/// opening the file means finding the secret and this derivation in a release's binary. That raises
/// the cost and keeps the repository and the hosted files from opening it alone, but a determined
/// person with a release on their own Mac can still do it, so it stays obfuscation. Everything here
/// is internal, so the framework exports no function that derives the key. A test pins the
/// derivation, so a refactor can't change it and strand installed releases.
enum FirmwareModelKey {
    /// The secret's length in bytes, and the keys'.
    static let byteCount = 32
    /// Masks `FirmwareBakedSecret`, so the secret is not a contiguous literal in the binary.
    static let secretMask: [UInt8] = [0xA7, 0x42, 0xDE, 0x19, 0x5C, 0xF3, 0x8E, 0x2B, 0x70, 0xC6, 0x11, 0x9D]

    /// The salt, assembled from the pieces spread across the Firmware sources.
    static var salt: Data {
        Data(FirmwareKeySaltA.bytes + FirmwareKeySaltB.bytes + FirmwareKeySaltC.bytes)
    }

    /// The release secret this build carries, or nil in a build from source.
    static var bakedSecret: SymmetricKey? {
        secret(fromMasked: FirmwareBakedSecret.masked)
    }

    /// Unmasks a secret stored as `masked`; nil unless it has `byteCount` bytes.
    static func secret(fromMasked masked: [UInt8]) -> SymmetricKey? {
        guard masked.count == byteCount else { return nil }
        var bytes = masked.enumerated().map { $0.element ^ secretMask[$0.offset % secretMask.count] }
        defer { bytes.wipe() }
        return SymmetricKey(data: bytes)
    }

    /// The masked form of `secret`, as the kept config carries it and `mise run release` writes
    /// it into `FirmwareBakedSecret`; the raw secret never leaves this.
    static func masked(secret: SymmetricKey) -> [UInt8] {
        secret.withUnsafeBytes { bytes in
            bytes.enumerated().map { $0.element ^ secretMask[$0.offset % secretMask.count] }
        }
    }

    /// The inner key for `secret` and a signing identity's Team ID: the running app's at
    /// runtime, the release's at pack time.
    static func innerKey(secret: SymmetricKey, teamIdentifier: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret, salt: salt,
            info: Data("redlamp.firmware.model.inner.v1|\(teamIdentifier)".utf8), outputByteCount: byteCount,
        )
    }
}

extension [UInt8] {
    /// Overwrites the bytes with zeros where they are, which `memset_s` does even when the
    /// array isn't read again.
    mutating func wipe() {
        withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            _ = memset_s(base, raw.count, 0, raw.count)
        }
    }
}

extension Data {
    /// Overwrites the bytes with zeros where they are. It clears only the storage this value
    /// holds alone: a copy made earlier, by a decoder or by copy-on-write, keeps its bytes.
    mutating func wipe() {
        let count = count
        guard count > 0 else { return }
        withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = memset_s(base, count, 0, count)
        }
    }
}
