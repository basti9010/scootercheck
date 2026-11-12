import Foundation
import zlib

/// Minimaler ZIP-Leser (Local File Headers): STORE + DEFLATE (zlib raw).
enum MinimalZipReader {
    struct Entry: Equatable, Sendable {
        var name: String
        var data: Data
    }

    enum Error: Swift.Error, LocalizedError {
        case invalidArchive
        case unsupportedCompression(UInt16)
        case inflateFailed
        case truncated

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "Keine gültige ZIP-Datei."
            case .unsupportedCompression(let m): return "Nicht unterstützte ZIP-Kompression (\(m))."
            case .inflateFailed: return "ZIP-Eintrag konnte nicht entpackt werden."
            case .truncated: return "ZIP-Datei ist unvollständig."
            }
        }
    }

    static func entries(from data: Data) throws -> [Entry] {
        var offset = 0
        var out: [Entry] = []
        while offset + 30 <= data.count {
            let sig = u32(data, offset)
            if sig == 0x0201_4B50 || sig == 0x0605_4B50 { break }
            guard sig == 0x0403_4B50 else {
                if out.isEmpty { throw Error.invalidArchive }
                break
            }
            let method = u16(data, offset + 8)
            let general = u16(data, offset + 6)
            let hasDataDescriptor = (general & 0x08) != 0
            let compSizeField = Int(u32(data, offset + 18))
            let uncompSize = Int(u32(data, offset + 22))
            let nameLen = Int(u16(data, offset + 26))
            let extraLen = Int(u16(data, offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + nameLen + extraLen
            guard nameStart + nameLen <= data.count else { throw Error.truncated }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(decoding: nameData, as: UTF8.self)

            let compSize: Int
            if hasDataDescriptor && compSizeField == 0 {
                // Selten in Firmware-ZIPs; ohne Central Directory nicht robust — abbrechen.
                throw Error.unsupportedCompression(method)
            } else {
                compSize = compSizeField
            }
            guard dataStart + compSize <= data.count else { throw Error.truncated }
            let compressed = data.subdata(in: dataStart..<(dataStart + compSize))
            let payload: Data
            switch method {
            case 0:
                payload = compressed
            case 8:
                payload = try inflateRaw(compressed, expectedUncompressed: uncompSize)
            default:
                throw Error.unsupportedCompression(method)
            }
            if !name.hasSuffix("/") {
                out.append(Entry(name: name, data: payload))
            }
            offset = dataStart + compSize
        }
        guard !out.isEmpty else { throw Error.invalidArchive }
        return out
    }

    private static func u16(_ data: Data, _ o: Int) -> UInt16 {
        UInt16(data[o]) | (UInt16(data[o + 1]) << 8)
    }

    private static func u32(_ data: Data, _ o: Int) -> UInt32 {
        UInt32(data[o])
            | (UInt32(data[o + 1]) << 8)
            | (UInt32(data[o + 2]) << 16)
            | (UInt32(data[o + 3]) << 24)
    }

    private static func inflateRaw(_ compressed: Data, expectedUncompressed: Int) throws -> Data {
        var stream = z_stream()
        let initStatus = compressed.withUnsafeBytes { src -> Int32 in
            guard let base = src.bindMemory(to: Bytef.self).baseAddress else { return Z_STREAM_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(compressed.count)
            // Negative windowBits = raw DEFLATE (ZIP).
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initStatus == Z_OK else { throw Error.inflateFailed }
        defer { inflateEnd(&stream) }

        let capacity = max(expectedUncompressed, max(compressed.count * 2, 256))
        var output = Data(count: capacity)
        var total = 0
        while true {
            let status: Int32 = output.withUnsafeMutableBytes { dst in
                guard let base = dst.bindMemory(to: Bytef.self).baseAddress else { return Z_STREAM_ERROR }
                stream.next_out = base.advanced(by: total)
                stream.avail_out = uInt(output.count - total)
                return inflate(&stream, Z_NO_FLUSH)
            }
            total = Int(stream.total_out)
            if status == Z_STREAM_END { break }
            if status == Z_BUF_ERROR || stream.avail_out == 0 {
                output.count += max(capacity, 4096)
                continue
            }
            if status != Z_OK { throw Error.inflateFailed }
            if stream.avail_in == 0 { break }
        }
        output.count = total
        return output
    }
}
