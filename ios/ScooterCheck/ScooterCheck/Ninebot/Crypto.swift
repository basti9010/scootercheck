import Foundation
import CommonCrypto

// MARK: - Protocol generation

enum ProtocolGen: String, Codable, CaseIterable {
    case gen2
    case gen3
}

// MARK: - Errors

enum BleError: LocalizedError {
    case encryptionFailed
    case macMismatch
    case replayDetected
    case invalidFrame
    case handshakeFailed(String)
    case timeout
    case notConnected

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .macMismatch: return "MAC verification failed"
        case .replayDetected: return "Replay counter rejected"
        case .invalidFrame: return "Invalid frame"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .timeout: return "Zeitüberschreitung bei BLE"
        case .notConnected: return "Keine Verbindung zum Scooter"
    }
    }
}

// MARK: - fw_data constant (Gen2 non-SN ECB input)

enum NbCryptoConstants {
    static let fwData: [UInt8] = [
        0x97, 0xCF, 0xB8, 0x02, 0x84, 0x41, 0x43, 0xDE,
        0x56, 0x00, 0x2B, 0x3B, 0x34, 0x78, 0x0A, 0x5D,
    ]
}

// MARK: - NbCrypto (Encryption2)

final class NbCrypto {
    private var key1 = Data()
    private var key2: Data?
    private var auth = Data(repeating: 0, count: 16)
    private var counter: Int = 0
    private let ecbInput: Data
    /// Gen2/SHU: fehlendes key2 → fw_data (nicht Nullen). Gen3: Nullen.
    private let defaultKey2IsFwData: Bool

    init(gen: ProtocolGen = .gen2) {
        if gen == .gen2 {
            ecbInput = Data(NbCryptoConstants.fwData)
            defaultKey2IsFwData = true
        } else {
            ecbInput = Data(repeating: 0, count: 16)
            defaultKey2IsFwData = false
        }
    }

    func setKey(_ key1: Data, _ key2: Data?) {
        self.key1 = key1
        self.key2 = key2
    }

    func setAuthParam(_ auth: Data) {
        self.auth = auth.prefix(16)
        if self.auth.count < 16 {
            self.auth.append(Data(repeating: 0, count: 16 - self.auth.count))
        }
    }

    func startSN() {
        counter = 1
    }

    func resetSN() {
        counter = 0
    }

    var snMode: Bool { counter > 0 }

    // MARK: - Encrypt / Decrypt

    func encrypt(_ plaintext: Data) throws -> Data {
        let aesKey = try deriveKey(key1: key1, key2: key2)
        let header = plaintext.prefix(3)

        if counter > 0 {
            return try encryptSN(aesKey: aesKey, plaintext: plaintext, header: Data(header))
        }
        return try encryptNonSN(aesKey: aesKey, plaintext: plaintext, header: Data(header))
    }

    func decrypt(_ cipherframe: Data) throws -> Data {
        guard cipherframe.count >= 9 else { throw BleError.invalidFrame }

        let aesKey = try deriveKey(key1: key1, key2: key2)
        let header = cipherframe.prefix(3)
        let tail = cipherframe.suffix(6)
        let encBody = cipherframe.subdata(in: 3..<(cipherframe.count - 6))

        let recvCounter = Int(tail[tail.startIndex + 4]) << 8 | Int(tail[tail.startIndex + 5])

        if recvCounter > 0 {
            return try decryptSN(
                aesKey: aesKey,
                header: Data(header),
                encBody: encBody,
                tail: Data(tail),
                recvCounter: recvCounter
            )
        }
        return try decryptNonSN(aesKey: aesKey, header: Data(header), encBody: encBody, tail: Data(tail))
    }

    // MARK: - SN mode

    private func encryptSN(aesKey: Data, plaintext: Data, header: Data) throws -> Data {
        counter += 1
        let ctr = counter
        let nonce = buildNonce(counter: ctr, auth: auth)
        let rawTag = try cbcMAC(aesKey: aesKey, plaintext: plaintext, nonce: nonce)
        let ciphertext = try ctrXOR(aesKey: aesKey, data: plaintext.subdata(in: 3..<plaintext.count), nonce: nonce, startBlock: 1)

        let a0KS = try aesECBOne(key: aesKey, block: buildABlock(nonce: nonce, blockIndex: 0))
        var encTag = Data()
        for i in 0..<4 {
            encTag.append(rawTag[i] ^ a0KS[i])
        }

        var ctrTail = Data()
        ctrTail.append(UInt8((ctr >> 8) & 0xFF))
        ctrTail.append(UInt8(ctr & 0xFF))

        var out = Data()
        out.append(header)
        out.append(ciphertext)
        out.append(encTag)
        out.append(ctrTail)
        return out
    }

    private func decryptSN(
        aesKey: Data,
        header: Data,
        encBody: Data,
        tail: Data,
        recvCounter: Int
    ) throws -> Data {
        if recvCounter <= (counter & 0xFFFF) && counter > 0 {
            throw BleError.replayDetected
        }

        let nonce = buildNonce(counter: recvCounter, auth: auth)
        let plaintextPayload = try ctrXOR(aesKey: aesKey, data: encBody, nonce: nonce, startBlock: 1)

        let encTag = tail.prefix(4)
        let a0KS = try aesECBOne(key: aesKey, block: buildABlock(nonce: nonce, blockIndex: 0))
        var recvTag = Data()
        for i in 0..<4 {
            recvTag.append(encTag[encTag.startIndex + i] ^ a0KS[i])
        }

        var plaintext = Data()
        plaintext.append(header)
        plaintext.append(plaintextPayload)

        let expectedTag = try cbcMAC(aesKey: aesKey, plaintext: plaintext, nonce: nonce)
        guard recvTag == expectedTag else { throw BleError.macMismatch }

        if recvCounter > counter {
            counter = recvCounter
        }
        return plaintext
    }

    // MARK: - Non-SN mode

    private func encryptNonSN(aesKey: Data, plaintext: Data, header: Data) throws -> Data {
        let payload = plaintext.subdata(in: 3..<plaintext.count)
        let checksum = (~payload.reduce(0) { $0 + Int($1) }) & 0xFFFF
        let keystream = try aesECBOne(key: aesKey, block: ecbInput)

        var out = Data()
        out.append(header)
        var offset = 0
        while offset < payload.count {
            let chunkLen = min(16, payload.count - offset)
            for j in 0..<chunkLen {
                out.append(payload[payload.startIndex + offset + j] ^ keystream[j])
            }
            offset += chunkLen
        }

        var tail = Data([0x00, 0x00, UInt8(checksum & 0xFF), UInt8((checksum >> 8) & 0xFF), 0x00, 0x00])
        out.append(tail)
        return out
    }

    private func decryptNonSN(aesKey: Data, header: Data, encBody: Data, tail: Data) throws -> Data {
        let keystream = try aesECBOne(key: aesKey, block: ecbInput)
        var payload = Data()
        var offset = 0
        while offset < encBody.count {
            let chunkLen = min(16, encBody.count - offset)
            for j in 0..<chunkLen {
                payload.append(encBody[encBody.startIndex + offset + j] ^ keystream[j])
            }
            offset += chunkLen
        }

        var plaintext = Data()
        plaintext.append(header)
        plaintext.append(payload)

        let expected = (~payload.reduce(0) { $0 + Int($1) }) & 0xFFFF
        let recv = Int(tail[tail.startIndex + 2]) | (Int(tail[tail.startIndex + 3]) << 8)
        guard expected == recv else { throw BleError.macMismatch }
        return plaintext
    }

    // MARK: - Primitives

    private func deriveKey(key1: Data, key2: Data?) throws -> Data {
        var k1 = key1
        if k1.count < 16 { k1.append(Data(repeating: 0, count: 16 - k1.count)) }
        k1 = k1.prefix(16)

        // SHU / NinebotCrypto / Max-G3-Flasher: bei null-key2 Gen2 → fw_data, nicht Nullen.
        let k2: Data
        if let key2 {
            var padded = key2
            if padded.count < 16 { padded.append(Data(repeating: 0, count: 16 - padded.count)) }
            k2 = padded.prefix(16)
        } else if defaultKey2IsFwData {
            k2 = Data(NbCryptoConstants.fwData)
        } else {
            k2 = Data(repeating: 0, count: 16)
        }

        let combined = k1 + k2
        let hash = sha1(combined)
        return hash.prefix(16)
    }

    private func buildNonce(counter: Int, auth: Data) -> Data {
        var nonce = Data()
        nonce.append(UInt8((counter >> 24) & 0xFF))
        nonce.append(UInt8((counter >> 16) & 0xFF))
        nonce.append(UInt8((counter >> 8) & 0xFF))
        nonce.append(UInt8(counter & 0xFF))
        nonce.append(auth.prefix(8))
        nonce.append(0x00)
        return nonce
    }

    private func buildABlock(nonce: Data, blockIndex: Int) -> Data {
        var block = Data([0x01])
        block.append(nonce)
        block.append(0x00)
        block.append(UInt8(blockIndex & 0xFF))
        if block.count < 16 {
            block.append(Data(repeating: 0, count: 16 - block.count))
        }
        return block.prefix(16)
    }

    private func buildB0(nonce: Data, payloadLen: Int) -> Data {
        var block = Data([0x59])
        block.append(nonce)
        block.append(0x00)
        block.append(UInt8(payloadLen & 0xFF))
        if block.count < 16 {
            block.append(Data(repeating: 0, count: 16 - block.count))
        }
        return block.prefix(16)
    }

    private func cbcMAC(aesKey: Data, plaintext: Data, nonce: Data) throws -> Data {
        let payloadLen = plaintext.count - 3
        var x = try aesECBOne(key: aesKey, block: buildB0(nonce: nonce, payloadLen: payloadLen))

        var aad = plaintext.prefix(3)
        aad.append(Data(repeating: 0, count: 13))
        x = try aesECBOne(key: aesKey, block: xor16(x, aad))

        let payload = plaintext.subdata(in: 3..<plaintext.count)
        var offset = 0
        while offset < payload.count {
            let end = min(offset + 16, payload.count)
            var chunk = payload.subdata(in: offset..<end)
            if chunk.count < 16 {
                chunk.append(Data(repeating: 0, count: 16 - chunk.count))
            }
            x = try aesECBOne(key: aesKey, block: xor16(x, chunk))
            offset += 16
        }
        return x.prefix(4)
    }

    private func ctrXOR(aesKey: Data, data: Data, nonce: Data, startBlock: Int) throws -> Data {
        var out = Data()
        var blockIndex = startBlock
        var offset = 0
        while offset < data.count {
            let ks = try aesECBOne(key: aesKey, block: buildABlock(nonce: nonce, blockIndex: blockIndex))
            let chunkLen = min(16, data.count - offset)
            for j in 0..<chunkLen {
                out.append(data[data.startIndex + offset + j] ^ ks[j])
            }
            offset += chunkLen
            blockIndex += 1
        }
        return out
    }

    private func xor16(_ a: Data, _ b: Data) -> Data {
        var out = Data()
        for i in 0..<16 {
            let av = i < a.count ? a[a.startIndex + i] : 0
            let bv = i < b.count ? b[b.startIndex + i] : 0
            out.append(av ^ bv)
        }
        return out
    }

    private func aesECBOne(key: Data, block: Data) throws -> Data {
        var out = Data(count: kCCBlockSizeAES128)
        var outLength = 0
        let status = key.withUnsafeBytes { keyPtr in
            block.withUnsafeBytes { blockPtr in
                out.withUnsafeMutableBytes { outPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyPtr.baseAddress, key.count,
                        nil,
                        blockPtr.baseAddress, kCCBlockSizeAES128,
                        outPtr.baseAddress, kCCBlockSizeAES128,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BleError.encryptionFailed }
        return out.prefix(outLength)
    }

    // MARK: - Hashing

    static func sha1(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    static func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    private func sha1(_ data: Data) -> Data { Self.sha1(data) }
}

// MARK: - Password generation

func generatePassword(auth: Data, timeMs: Int64? = nil) -> Data {
    let now = timeMs ?? Int64(Date().timeIntervalSince1970 * 1000)
    var j: Int64 = 0
    for (i, byte) in auth.enumerated() {
        let signed = Int64(byte > 127 ? Int(byte) - 256 : Int(byte))
        let shift = (i % 8) * 8
        let val = javaInt(signed << (shift & 31))
        j = javaLong(j + Int64(val))
    }
    let seed = javaLong(now + j)
    let randomBytes = JavaRandom(seed: seed).nextBytes(16)
    return NbCrypto.sha256(randomBytes).prefix(16)
}

func ascii(_ data: Data) -> String {
    String(data: data, encoding: .ascii) ?? Nb.hex(data)
}

// MARK: - Java-compatible helpers

private func javaInt(_ value: Int64) -> Int32 {
    Int32(truncatingIfNeeded: value)
}

private func javaLong(_ value: Int64) -> Int64 {
    value
}

private final class JavaRandom {
    private var seed: UInt64
    private static let mask: UInt64 = (1 << 48) - 1
    private static let multiplier: UInt64 = 0x5DEECE66D
    private static let addend: UInt64 = 0xB

    init(seed: Int64) {
        let s = UInt64(bitPattern: seed)
        self.seed = (s ^ Self.multiplier) & Self.mask
    }

    private func next(bits: Int) -> UInt32 {
        seed = (seed &* Self.multiplier &+ Self.addend) & Self.mask
        return UInt32(seed >> (48 - bits))
    }

    func nextBytes(_ count: Int) -> Data {
        var out = Data(count: count)
        var index = 0
        while index < count {
            let rnd = next(bits: 32)
            for j in 0..<min(4, count - index) {
                out[index] = UInt8((rnd >> (8 * j)) & 0xFF)
                index += 1
            }
        }
        return out
    }
}
