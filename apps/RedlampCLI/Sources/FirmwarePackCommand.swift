import Foundation
import RedlampRecipes

/// `redlamp recipe firmware-pack`: the firmware model's hosted files, sealed for release builds
/// (TON-50) through `FirmwareModelPacking`, the app's own code, so the format can't drift.
///
/// It writes the two files to host, `tables.bin` and `key.bin`, into `--out`. The secret lives in
/// the kept config `--config` names, `Firmware.local.xcconfig`, which `mise run release` reads: when
/// that file exists its secret is used again, so a reseal opens on the releases already out; when it
/// doesn't, a new secret is made and the config written there. The secret never goes on the command
/// line, an existing config is never overwritten, and the config is never written beside the files
/// to host. Neither folder may be in a checkout, since none of these files is ever committed.
enum FirmwarePackCommand {
    static let valued: Set<String> = ["--model", "--team", "--config", "--tables-file", "--key-file"]

    static func run(_ context: RecipeCommands.Context) async throws {
        let arguments = context.arguments
        if arguments.has("--check") {
            try await check(arguments)
            return
        }
        guard let out = arguments.value("--out").map(expanded),
              let config = arguments.value("--config").map(expanded)
        else {
            throw CLIError(
                description: "firmware-pack needs --out <folder for the files to host> and --config <kept config>",
            )
        }
        for url in [out, config] where insideCheckout(url) {
            throw CLIError(
                description: "\(url.path) is in a checkout; the sealed files and the config are never committed",
            )
        }
        guard out.standardizedFileURL.path != config.deletingLastPathComponent().standardizedFileURL.path else {
            throw CLIError(description: "keep --config out of --out, so the config isn't uploaded with the files")
        }
        let folder = arguments.value("--model").map(expanded)
            ?? FirmwareFilmModel.environmentFolder ?? FirmwareFilmModel.defaultFolder
        guard let team = arguments.value("--team") ?? ProcessInfo.processInfo.environment["REDLAMP_TEAM_ID"],
              FirmwareModelPacking.isTeamIdentifier(team)
        else { throw CLIError(description: "firmware-pack needs --team, the release's ten-character Team ID") }

        let kept = FileManager.default.fileExists(atPath: config.path)
        let output: FirmwareModelPacking.Output
        if kept {
            guard let masked = maskedSecret(in: config) else {
                throw CLIError(
                    description: "\(config.path) has no REDLAMP_FIRMWARE_SECRET_MASKED, so it isn't a kept config",
                )
            }
            output = try FirmwareModelPacking.reseal(modelFolder: folder, team: team, maskedSecret: masked)
        } else {
            output = try FirmwareModelPacking.sealWithNewSecret(modelFolder: folder, team: team)
        }
        try makeFolder(out)
        try write(output.sealed, to: out.appending(path: "tables.bin"))
        try write(output.outerKey, to: out.appending(path: "key.bin"))
        if !kept {
            try makeFolder(config.deletingLastPathComponent())
            try write(Data(keptConfig(masked: output.maskedSecret).utf8), to: config)
        }
        print("""
        Sealed \(output.simulationCount) simulations for Team ID \(team), \(output.sealed.count) bytes, to host:
          \(out.appending(path: "tables.bin").path)   at the tables address
          \(out.appending(path: "key.bin").path)      at the key address
        \(kept
            ? "The secret is the one in \(config.path), so releases already out open it; host both files again."
            :
            "A new secret is in \(config.path): fill in both addresses once the files are hosted, keep a copy safe (installed releases need it), and never commit it.")
        """)
    }

    /// The config `Version.xcconfig` includes once `mise run release` has put it in place: the two
    /// addresses, empty until the files are hosted, and the masked secret. `//` starts a comment in
    /// an xcconfig, so an address is written `https:/$()/…`.
    static func keptConfig(masked: [UInt8]) -> String {
        """
        // The firmware model's hosted files for release builds (TON-50). Keep this file safe and never
        // commit it: `mise run release` reads it, and refuses to build without it. Write each address
        // as https:/$()/host/path, since `//` starts a comment here. The secret never changes, since
        // installed releases need it to open the hosted file.
        REDLAMP_FIRMWARE_TABLES_URL =
        REDLAMP_FIRMWARE_KEY_URL =
        REDLAMP_FIRMWARE_SECRET_MASKED = \(masked.map { String(format: "%02x", $0) }.joined())

        """
    }

    /// `--check`: fetches both hosted files from the kept config's addresses and opens them with its
    /// secret, as a release signed by `--team` would, so a mismatch shows before users meet it.
    /// `--tables-file` and `--key-file` give copies already fetched, as `mise run release` does with
    /// curl, which goes through a proxy where URLSession doesn't.
    static func check(_ arguments: Arguments) async throws {
        guard let config = arguments.value("--config").map(expanded) else {
            throw CLIError(description: "firmware-pack --check needs --config <kept config>")
        }
        guard let team = arguments.value("--team") ?? ProcessInfo.processInfo.environment["REDLAMP_TEAM_ID"],
              FirmwareModelPacking.isTeamIdentifier(team)
        else { throw CLIError(description: "firmware-pack needs --team, the release's ten-character Team ID") }
        guard let masked = maskedSecret(in: config) else {
            throw CLIError(
                description: "\(config.path) has no REDLAMP_FIRMWARE_SECRET_MASKED, so it isn't a kept config",
            )
        }
        guard let tables = address("REDLAMP_FIRMWARE_TABLES_URL", in: config),
              let key = address("REDLAMP_FIRMWARE_KEY_URL", in: config)
        else { throw CLIError(description: "\(config.path) doesn't have both addresses as https addresses yet") }
        func file(_ option: String, else url: URL) async throws -> Data {
            if let path = arguments.value(option) {
                return try Data(contentsOf: expanded(path))
            }
            return try await fetch(url)
        }
        let sealed = try await file("--tables-file", else: tables)
        let outerKey = try await file("--key-file", else: key)
        let count = try FirmwareModelPacking.check(sealed: sealed, outerKey: outerKey, team: team, maskedSecret: masked)
        print("The hosted files open as a release signed by \(team) would: \(count) simulations")
    }

    /// The masked secret in a kept config.
    static func maskedSecret(in config: URL) -> [UInt8]? {
        setting("REDLAMP_FIRMWARE_SECRET_MASKED", in: config).flatMap(bytes(hex:))
    }

    /// An address in a kept config, as Xcode will read it once the `$()` that guards its `//` is gone.
    static func address(_ name: String, in config: URL) -> URL? {
        guard let value = setting(name, in: config)?.replacingOccurrences(of: "$()", with: ""),
              let url = URL(string: value), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    private static func setting(_ name: String, in config: URL) -> String? {
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == name {
                return parts[1]
            }
        }
        return nil
    }

    /// One hosted file, over an ephemeral session so it isn't cached on disk.
    private static func fetch(_ url: URL) async throws -> Data {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(
            for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30),
        )
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw CLIError(
                description: "\(url.absoluteString) answered \((response as? HTTPURLResponse)?.statusCode ?? 0)",
            )
        }
        return data
    }

    /// Whether `url`, or a folder above it, is a Redlamp checkout.
    private static func insideCheckout(_ url: URL) -> Bool {
        var folder = url.standardizedFileURL
        while folder.path != "/" {
            if FileManager.default.fileExists(atPath: folder.appending(path: "Workspace.swift").path) {
                return true
            }
            folder.deleteLastPathComponent()
        }
        return false
    }

    private static func bytes(hex: String) -> [UInt8]? {
        let digits = Array(hex.utf8)
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(decoding: digits[index ..< index + 2], as: UTF8.self), radix: 16)
            else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    private static func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700],
        )
    }

    /// Created readable by the owner only, never with wider permissions first.
    private static func write(_ data: Data, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw CLIError(description: "couldn't write \(url.path)") }
    }

    private static func expanded(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
