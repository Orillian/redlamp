import Foundation

/// The release secret the firmware model's inner key needs (TON-50), XOR-masked with
/// `FirmwareModelKey.secretMask`.
///
/// Empty in the repository and in every build from source, so those builds carry no secret and the
/// hosted model is unavailable; development and tests read the model folder instead. For a release,
/// `mise run release` replaces this file, in its throwaway build worktree only, with the masked
/// bytes of the secret it reads from the kept `Firmware.local.xcconfig`, which is never committed.
/// The secret never changes, since installed releases need it to derive the same inner key.
enum FirmwareBakedSecret {
    static let masked: [UInt8] = []
}
