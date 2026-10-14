import Compression
import CryptoKit
import Foundation

/// The firmware model's four files packed into one opaque blob and sealed twice with AES-GCM
/// (TON-50): the inner seal under `FirmwareModelKey.innerKey`, the outer seal under a random key
/// hosted beside the file. The packed form is positional and compressed, so it carries no file
/// names and doesn't read as JSON; sealed, it is indistinguishable from random bytes.
///
/// `seal` builds the hosted file and `open` reverses it, wiping each plaintext buffer it makes.
/// Both take their keys as arguments, so they round-trip in tests on synthetic files, with no
/// network, no real model and no signature. They are internal: the framework a release ships
/// exports no function that opens the file, only `FirmwareModelPacking`'s, which seal.
enum FirmwareModelPack {
    enum PackError: Error, Equatable, CustomStringConvertible {
        case format(String)
        case outerSeal
        case innerSeal

        var description: String {
            switch self {
            case let .format(what): "the firmware pack's \(what)"
            case .outerSeal: "the firmware pack's outer seal didn't open: the hosted key is wrong or the file is damaged"
            case .innerSeal: "the firmware pack's inner seal didn't open: this build can't derive its key"
            }
        }
    }

    /// Generic bytes that mark the packed form; not a word, so the plaintext names nothing.
    private static let magic: [UInt8] = [0xF5, 0x3D, 0xA1, 0x01]
    /// The four files, in `FirmwareFilmModel.fileNames` order.
    private static let entryCount = 4
    /// A bound on the unpacked size, far above the model's, so a damaged length can't ask for
    /// an arbitrary allocation.
    private static let maximumSize = 64 << 20

    /// Packs the four files, seals the blob under `innerKey`, then seals that under `outerKey`:
    /// the file to host, beside `outerKey`.
    static func seal(_ files: FirmwareFilmModel.Files, innerKey: SymmetricKey, outerKey: SymmetricKey) throws -> Data {
        var packed = try pack(files)
        defer { packed.wipe() }
        var inner = try combined(AES.GCM.seal(packed, using: innerKey))
        defer { inner.wipe() }
        return try combined(AES.GCM.seal(inner, using: outerKey))
    }

    /// Opens the outer seal with `outerKey` and the inner with `innerKey`, and unpacks the four
    /// files, wiping each plaintext buffer it made on the way. The caller wipes the files once
    /// it has parsed them.
    static func open(_ sealed: Data, outerKey: SymmetricKey, innerKey: SymmetricKey) throws -> FirmwareFilmModel.Files {
        var inner: Data
        do {
            inner = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: outerKey)
        } catch {
            throw PackError.outerSeal
        }
        defer { inner.wipe() }
        var packed: Data
        do {
            packed = try AES.GCM.open(AES.GCM.SealedBox(combined: inner), using: innerKey)
        } catch {
            throw PackError.innerSeal
        }
        defer { packed.wipe() }
        return try unpack(packed)
    }

    // MARK: - The packed form

    /// `magic`, the body's length (UInt32, little-endian), then the body compressed with LZFSE.
    /// The body is the entry count, then each file's length (UInt32, little-endian) and bytes.
    private static func pack(_ files: FirmwareFilmModel.Files) throws -> Data {
        let entries = [files.parameters, files.toneGains, files.calibration, files.constants]
        var body = Data([UInt8(entries.count)])
        for entry in entries {
            guard entry.count <= maximumSize else { throw PackError.format("file is too large") }
            body.append(littleEndian: UInt32(entry.count))
            body.append(entry)
        }
        defer { body.wipe() }
        guard body.count <= maximumSize else { throw PackError.format("files are too large") }
        var compressed = try compress(body)
        defer { compressed.wipe() }
        var packed = Data(magic)
        packed.append(littleEndian: UInt32(body.count))
        packed.append(compressed)
        return packed
    }

    private static func unpack(_ packed: Data) throws -> FirmwareFilmModel.Files {
        var reader = Reader(packed)
        guard reader.bytes(magic.count) == magic, let size = reader.uint32().map(Int.init), size <= maximumSize
        else { throw PackError.format("header isn't one this build reads") }
        var compressed = reader.rest()
        defer { compressed.wipe() }
        var body = try decompress(compressed, size: size)
        defer { body.wipe() }
        var entries = Reader(body)
        guard entries.bytes(1) == [UInt8(entryCount)] else { throw PackError.format("file count isn't four") }
        var files: [Data] = []
        for _ in 0 ..< entryCount {
            guard let length = entries.uint32().map(Int.init), let data = entries.data(length) else {
                throw PackError.format("files are cut short")
            }
            files.append(data)
        }
        guard entries.isAtEnd else { throw PackError.format("body has bytes after the files") }
        return FirmwareFilmModel.Files(
            parameters: files[0], toneGains: files[1], calibration: files[2], constants: files[3],
        )
    }

    private static func combined(_ box: AES.GCM.SealedBox) throws -> Data {
        guard let combined = box.combined else { throw PackError.format("seal has no combined form") }
        return combined
    }

    /// LZFSE into a buffer of this value's own, with a scratch buffer of its own too, so `wipe`
    /// reaches both.
    private static func compress(_ data: Data) throws -> Data {
        let capacity = data.count + 4096
        var out = Data(count: capacity)
        var scratch = Data(count: compression_encode_scratch_buffer_size(COMPRESSION_LZFSE))
        defer { scratch.wipe() }
        let written = out.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                scratch.withUnsafeMutableBytes { work in
                    compression_encode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!, data.count, work.baseAddress,
                        COMPRESSION_LZFSE,
                    )
                }
            }
        }
        guard written > 0 else {
            out.wipe()
            throw PackError.format("body didn't compress")
        }
        out.count = written
        return out
    }

    /// Decompresses into a buffer of exactly `size` bytes, with a scratch buffer, both owned here,
    /// so `wipe` reaches every copy of the plaintext the decoder writes.
    private static func decompress(_ data: Data, size: Int) throws -> Data {
        guard size > 0, !data.isEmpty else { throw PackError.format("body is empty") }
        var out = Data(count: size)
        var scratch = Data(count: compression_decode_scratch_buffer_size(COMPRESSION_LZFSE))
        defer { scratch.wipe() }
        let written = out.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                scratch.withUnsafeMutableBytes { work in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, size,
                        source.bindMemory(to: UInt8.self).baseAddress!, data.count, work.baseAddress,
                        COMPRESSION_LZFSE,
                    )
                }
            }
        }
        guard written == size else {
            out.wipe()
            throw PackError.format("body didn't decompress to its length")
        }
        return out
    }

    /// Reads the packed form's fields, bounds-checked.
    private struct Reader {
        private let data: Data
        private var offset: Int

        init(_ data: Data) {
            self.data = data
            offset = data.startIndex
        }

        var isAtEnd: Bool {
            offset == data.endIndex
        }

        mutating func data(_ count: Int) -> Data? {
            guard count >= 0, data.endIndex - offset >= count else { return nil }
            defer { offset += count }
            return Data(data[offset ..< offset + count])
        }

        mutating func bytes(_ count: Int) -> [UInt8]? {
            data(count).map(Array.init)
        }

        mutating func uint32() -> UInt32? {
            bytes(4).map { $0.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        }

        mutating func rest() -> Data {
            data(data.endIndex - offset) ?? Data()
        }
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

extension FirmwareFilmModel {
    /// The model opened from a hosted pack: the outer seal under the hosted `outerKey`, the inner
    /// under this build's `innerKey`. The four files are wiped once parsed; the parsed model stays,
    /// since every slider change re-bakes from it. Its `source` is the sealed file's digest, so a
    /// republished file doesn't serve a stale baked look.
    init(sealed: Data, outerKey: SymmetricKey, innerKey: SymmetricKey) throws {
        var files = try FirmwareModelPack.open(sealed, outerKey: outerKey, innerKey: innerKey)
        defer {
            files.parameters.wipe()
            files.toneGains.wipe()
            files.calibration.wipe()
            files.constants.wipe()
        }
        let digest = SHA256.hash(data: sealed).prefix(8).map { String(format: "%02x", $0) }.joined()
        try self.init(files: files, source: "hosted:\(digest)")
    }
}
