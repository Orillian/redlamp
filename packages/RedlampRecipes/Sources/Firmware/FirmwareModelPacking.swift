#if !REDLAMP_APP_STORE
    import CryptoKit
    import Foundation

    /// The firmware model sealed for release builds (TON-50): the one public way into the pack and
    /// the inner key, which `redlamp recipe firmware-pack` calls, so the hosted file is written by the
    /// same code the app opens it with. It only seals: it returns this pack's sealed file and its new
    /// outer key, and the secret masked as the kept config stores it, and nothing it exposes opens a
    /// file or derives the key of one already hosted.
    public enum FirmwareModelPacking {
        public struct Output: Sendable {
            /// The sealed model, for the tables address.
            public let sealed: Data
            /// Its outer key, new for each pack, for the key address.
            public let outerKey: Data
            /// The inner key's secret, masked, for the kept config.
            public let maskedSecret: [UInt8]
            public let simulationCount: Int
        }

        /// Seals the model folder's files for releases signed by `team` under a new secret: the first
        /// pack, after which every release must carry that secret.
        public static func sealWithNewSecret(modelFolder: URL, team: String) throws -> Output {
            try seal(modelFolder: modelFolder, team: team, secret: SymmetricKey(size: .bits256))
        }

        /// Seals them again under the secret a kept config holds, masked, so the releases already out
        /// open the new file.
        public static func reseal(modelFolder: URL, team: String, maskedSecret: [UInt8]) throws -> Output {
            guard let secret = FirmwareModelKey.secret(fromMasked: maskedSecret) else {
                throw FirmwareModelPack.PackError.format("kept secret isn't \(FirmwareModelKey.byteCount) bytes")
            }
            return try seal(modelFolder: modelFolder, team: team, secret: secret)
        }

        /// Whether `team` is a Team ID's form: ten capitals and digits.
        public static func isTeamIdentifier(_ team: String) -> Bool {
            team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
        }

        /// Opens hosted files as a release signed by `team` would, but with the secret the kept config
        /// holds rather than one baked in, and returns the number of simulations: the check that what's
        /// hosted matches the kept config. It needs that secret, so it opens nothing for anyone without it.
        public static func check(sealed: Data, outerKey: Data, team: String, maskedSecret: [UInt8]) throws -> Int {
            guard isTeamIdentifier(team) else { throw FirmwareModelPack.PackError.format("Team ID \(team) isn't one") }
            guard let secret = FirmwareModelKey.secret(fromMasked: maskedSecret) else {
                throw FirmwareModelPack.PackError.format("kept secret isn't \(FirmwareModelKey.byteCount) bytes")
            }
            guard outerKey.count == FirmwareModelKey.byteCount else {
                throw FirmwareModelPack.PackError.format("hosted key isn't \(FirmwareModelKey.byteCount) bytes")
            }
            let innerKey = FirmwareModelKey.innerKey(secret: secret, teamIdentifier: team)
            return try FirmwareFilmModel(sealed: sealed, outerKey: SymmetricKey(data: outerKey), innerKey: innerKey)
                .simulationNames.count
        }

        /// Seals, then opens the result with the same keys and checks it holds the folder's model,
        /// so a file that wouldn't open in a release is never handed over.
        private static func seal(modelFolder: URL, team: String, secret: SymmetricKey) throws -> Output {
            guard isTeamIdentifier(team) else { throw FirmwareModelPack.PackError.format("Team ID \(team) isn't one") }
            let innerKey = FirmwareModelKey.innerKey(secret: secret, teamIdentifier: team)
            let outerKey = SymmetricKey(size: .bits256)
            let files = try FirmwareFilmModel.Files(folder: modelFolder)
            let sealed = try FirmwareModelPack.seal(files, innerKey: innerKey, outerKey: outerKey)
            let opened = try FirmwareFilmModel(sealed: sealed, outerKey: outerKey, innerKey: innerKey)
            guard try opened.simulationNames == FirmwareFilmModel(folder: modelFolder).simulationNames else {
                throw FirmwareModelPack.PackError.format("sealed file didn't open to the folder's model")
            }
            return Output(
                sealed: sealed, outerKey: outerKey.withUnsafeBytes { Data($0) },
                maskedSecret: FirmwareModelKey.masked(secret: secret), simulationCount: opened.simulationNames.count,
            )
        }
    }
#endif
