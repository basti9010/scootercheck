import CryptoKit
import Foundation

enum FirmwareDigest {
    static func make(from data: Data) -> FirmwareFileDigest {
        FirmwareFileDigest(
            md5: md5Hex(data),
            sha256: sha256Hex(data),
            byteCount: data.count,
            shannonEntropy: shannonEntropy(data)
        )
    }

    static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Shannon entropy in bits/byte (0…8). High values (~7.5+) often indicate encryption/compression.
    static func shannonEntropy(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        for b in data { counts[Int(b)] += 1 }
        let n = Double(data.count)
        var h = 0.0
        for c in counts where c > 0 {
            let p = Double(c) / n
            h -= p * log2(p)
        }
        return h
    }
}
