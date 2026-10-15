#if !REDLAMP_APP_STORE
    import CryptoKit
    import Foundation

    /// Where the firmware model comes from while its switch is on (TON-50).
    public enum FirmwareModelSource: Equatable, Sendable {
        /// The model folder, when it holds the four files: development and tests.
        case folder(URL)
        /// The hosted file and its outer key, when the build carries their addresses: releases.
        case hosted(FirmwareModelHost.Addresses)
        /// Neither: a build from source without the folder.
        case unavailable
    }

    public extension FirmwareFilmModel {
        /// Where the model comes from as the settings and this build stand: the folder if it holds
        /// the files, else the hosted file if the build carries its addresses; nil while the switch
        /// is off.
        static func source(_ defaults: UserDefaults = .standard, bundle: Bundle = .main) -> FirmwareModelSource? {
            guard let folder = settingsFolder(defaults) else { return nil }
            if isAvailable(at: folder) {
                return .folder(folder)
            }
            if let addresses = FirmwareModelHost.Addresses(bundle: bundle) {
                return .hosted(addresses)
            }
            return .unavailable
        }
    }

    /// The firmware model's hosted file (TON-50): sealed twice (`FirmwareModelPack`), on the website
    /// at an address only release builds carry, beside its outer key at another. Only the sealed file
    /// is kept on disk; the outer key is fetched into memory each time, and the file opens in memory.
    /// Deleting either file on the website, or changing the key, turns the model off for everyone.
    public struct FirmwareModelHost: Sendable {
        /// The two addresses, which release builds get from the kept `Firmware.local.xcconfig` through
        /// Info.plist; the repository names neither.
        public struct Addresses: Equatable, Sendable {
            public var tables: URL
            public var key: URL

            public init(tables: URL, key: URL) {
                self.tables = tables
                self.key = key
            }

            /// The build's addresses, both HTTPS; nil in a build from source, whose keys are empty.
            public init?(bundle: Bundle) {
                func address(_ key: String) -> URL? {
                    guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                          let url = URL(string: value), url.scheme == "https", url.host() != nil else { return nil }
                    return url
                }
                guard let tables = address("RedlampFirmwareTablesURL"), let key = address("RedlampFirmwareKeyURL")
                else { return nil }
                self.init(tables: tables, key: key)
            }
        }

        /// Why the hosted model isn't open; it stays off until the switch is turned on again or the
        /// app relaunches.
        public enum Failure: Error, Equatable, CustomStringConvertible {
            /// The website no longer has the file or its key, so the copy kept here was deleted.
            case withdrawn
            /// The key couldn't be fetched, or neither a fetched nor a kept file could be had.
            case unreachable
            /// This build can't derive the inner key: a build from source, or a signature that isn't valid.
            case notThisBuild
            /// The file didn't open with the key and this build's inner key.
            case unopenable

            public var description: String {
                switch self {
                case .withdrawn: "The model has been withdrawn."
                case .unreachable: "Redlamp couldn't reach the model's files; turn this off and on to try again."
                case .notThisBuild: "This build can't open the hosted model."
                case .unopenable: "The model's file couldn't be opened."
                }
            }
        }

        /// The sealed file kept on this Mac, under a generic name.
        public static let keptFile = URL.applicationSupportDirectory.appending(path: "Redlamp/Film Model/tables.bin")

        let addresses: Addresses
        let keptFile: URL
        let timeout: TimeInterval
        let innerKey: @Sendable () -> SymmetricKey?

        public init(addresses: Addresses, keptFile: URL = FirmwareModelHost.keptFile) {
            self.init(addresses: addresses, keptFile: keptFile, timeout: 20, innerKey: Self.buildInnerKey)
        }

        init(
            addresses: Addresses, keptFile: URL, timeout: TimeInterval,
            innerKey: @escaping @Sendable () -> SymmetricKey?,
        ) {
            self.addresses = addresses
            self.keptFile = keptFile
            self.timeout = timeout
            self.innerKey = innerKey
        }

        /// The running app's inner key: its baked secret under its own valid signature's Team ID.
        static func buildInnerKey() -> SymmetricKey? {
            guard let secret = FirmwareModelKey.bakedSecret, let team = FirmwareSigningIdentity.current()
            else { return nil }
            return FirmwareModelKey.innerKey(secret: secret, teamIdentifier: team)
        }

        /// Re-checks the hosted file, fetches the outer key into memory and opens the file there.
        /// A 404 for either deletes the copy kept here; a new file replaces it once it has opened;
        /// when the website can't be reached, the kept copy is used if the key can be had. A host that
        /// answers Forbidden for a deleted file still turns the model off, since the key can't be had,
        /// but leaves the kept copy, useless without the key, until it answers Not Found.
        public func open() async -> Result<FirmwareFilmModel, Failure> {
            let fetched = await fetch(addresses.tables)
            if case .missing = fetched {
                withdraw()
                return .failure(.withdrawn)
            }
            // The outer key isn't a secret: a release's Info.plist names its address. So it's not wiped.
            let outerKey: SymmetricKey
            switch await fetch(addresses.key) {
            case .missing:
                withdraw()
                return .failure(.withdrawn)
            case .failed:
                return .failure(.unreachable)
            case let .found(bytes):
                guard bytes.count == FirmwareModelKey.byteCount else { return .failure(.unopenable) }
                outerKey = SymmetricKey(data: bytes)
            }
            guard let innerKey = innerKey() else { return .failure(.notThisBuild) }
            let kept = try? Data(contentsOf: keptFile)
            var candidates: [Data] = []
            if case let .found(sealed) = fetched {
                candidates.append(sealed)
            }
            if let kept, !candidates.contains(kept) {
                candidates.append(kept)
            }
            guard !candidates.isEmpty else { return .failure(.unreachable) }
            for sealed in candidates {
                guard let model = try? FirmwareFilmModel(sealed: sealed, outerKey: outerKey, innerKey: innerKey)
                else { continue }
                if sealed != kept {
                    keep(sealed)
                }
                return .success(model)
            }
            return .failure(.unopenable)
        }

        private enum Fetched {
            case found(Data)
            case missing
            case failed
        }

        /// An ephemeral session, so neither file lands in a URL cache on disk.
        private static let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        }()

        /// A file URL (tests) is read from disk, a missing file standing in for a 404.
        private func fetch(_ url: URL) async -> Fetched {
            if url.isFileURL {
                guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
                return (try? Data(contentsOf: url)).map(Fetched.found) ?? .failed
            }
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            guard let (data, response) = try? await Self.session.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
            switch status {
            case 200: return .found(data)
            case 404, 410: return .missing
            default: return .failed
            }
        }

        private func keep(_ sealed: Data) {
            try? FileManager.default.createDirectory(
                at: keptFile.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try? sealed.write(to: keptFile, options: .atomic)
        }

        private func withdraw() {
            try? FileManager.default.removeItem(at: keptFile)
        }
    }
#endif
