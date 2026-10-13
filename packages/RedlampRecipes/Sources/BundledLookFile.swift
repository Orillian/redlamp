import Foundation

/// A bundled look's file (`.look.lzma`): LZMA over a short header, the look's JSON with its
/// table's data left out, and the table's values. Each channel's little-endian Float16 values,
/// red fastest, are stored as their differences from the value before, channel after channel,
/// which compresses to less than half the size of the same table as base64 inside the JSON.
///
///     "RLLK" · the JSON's length (UInt32, little-endian) · the JSON · red's, green's, blue's differences
enum BundledLookFile {
    static let fileExtension = "look.lzma"
    private static let magic = Data("RLLK".utf8)
    private static let channels = 3

    enum ReadError: Error, Equatable {
        case notALook
        case badTable
    }

    static func encode(_ package: BaseLookPackage) throws -> Data {
        var header = package
        var values = Data()
        if let table = package.table {
            guard let bytes = Data(base64Encoded: table.data), bytes.count == byteCount(size: table.size) else {
                throw ReadError.badTable
            }
            values = differences(bytes)
            header.table?.data = ""
        }
        let json = try RecipeFile.encoder.encode(header)
        var file = magic
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(json)
        file.append(values)
        return try (file as NSData).compressed(using: .lzma) as Data
    }

    static func decode(_ data: Data) throws -> BaseLookPackage {
        let file = try (data as NSData).decompressed(using: .lzma) as Data
        let start = file.startIndex + magic.count + 4
        guard file.count >= magic.count + 4, file.prefix(magic.count) == magic else { throw ReadError.notALook }
        let length = file[file.startIndex + magic.count ..< start].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard file.endIndex - start >= length else { throw ReadError.notALook }
        var package = try RecipeFile.decoder.decode(BaseLookPackage.self, from: file[start ..< start + length])
        let values = file[(start + length)...]
        if let table = package.table {
            guard values.count == byteCount(size: table.size) else { throw ReadError.badTable }
            package.table?.data = Self.values(fromDifferences: Data(values)).base64EncodedString()
        } else if !values.isEmpty {
            throw ReadError.badTable
        }
        return package
    }

    private static func byteCount(size: Int) -> Int {
        size * size * size * channels * MemoryLayout<UInt16>.size
    }

    private static func differences(_ interleaved: Data) -> Data {
        let count = interleaved.count / (channels * MemoryLayout<UInt16>.size)
        var out = Data(count: interleaved.count)
        interleaved.withUnsafeBytes { source in
            out.withUnsafeMutableBytes { target in
                let values = source.bindMemory(to: UInt16.self)
                let differences = target.bindMemory(to: UInt16.self)
                for channel in 0 ..< channels {
                    var previous: UInt16 = 0
                    for index in 0 ..< count {
                        let value = UInt16(littleEndian: values[index * channels + channel])
                        differences[channel * count + index] = (value &- previous).littleEndian
                        previous = value
                    }
                }
            }
        }
        return out
    }

    private static func values(fromDifferences planar: Data) -> Data {
        let count = planar.count / (channels * MemoryLayout<UInt16>.size)
        var out = Data(count: planar.count)
        planar.withUnsafeBytes { source in
            out.withUnsafeMutableBytes { target in
                let differences = source.bindMemory(to: UInt16.self)
                let values = target.bindMemory(to: UInt16.self)
                for channel in 0 ..< channels {
                    var value: UInt16 = 0
                    for index in 0 ..< count {
                        value &+= UInt16(littleEndian: differences[channel * count + index])
                        values[index * channels + channel] = value.littleEndian
                    }
                }
            }
        }
        return out
    }
}
