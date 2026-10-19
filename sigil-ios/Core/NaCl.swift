import CryptoKit
import Foundation

/// The NaCl box, as Phantom uses it for its deeplink replies.
///
/// Phantom encrypts everything it sends back with `crypto_box`: an x25519 shared secret,
/// then XSalsa20-Poly1305. CryptoKit gives us the x25519 part and nothing else — it has no
/// XSalsa20 and no standalone Poly1305 — so the rest is here rather than pulling in a
/// dependency. Every piece is checked against libsodium's own output in `NaClTests`.
enum NaCl {
    // MARK: Box

    /// `crypto_box_beforenm`: the shared key for a conversation with one peer.
    ///
    /// Not the raw x25519 output — NaCl runs HSalsa20 over it with a zero nonce, and using
    /// the raw secret instead silently produces a key that decrypts nothing.
    static func sharedKey(theirPublicKey: Data, ourSecretKey: Data) throws -> Data {
        let secret = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ourSecretKey)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirPublicKey)
        let raw = try secret.sharedSecretFromKeyAgreement(with: peer)
        let rawBytes = raw.withUnsafeBytes { Data($0) }
        return hsalsa20(key: rawBytes, input: Data(repeating: 0, count: 16))
    }

    /// `crypto_box_open_afternm`: the ciphertext is the 16-byte tag followed by the body.
    static func open(_ box: Data, nonce: Data, sharedKey key: Data) -> Data? {
        guard box.count >= 16, nonce.count == 24 else { return nil }
        let tag = box.prefix(16)
        let body = box.dropFirst(16)

        // The first 32 bytes of the keystream are the one-time Poly1305 key; the message
        // starts after them.
        let stream = xsalsa20(key: key, nonce: nonce, count: body.count + 32)
        let expected = poly1305(message: Data(body), key: stream.prefix(32))
        // Constant time: a tag comparison that returns early leaks where it differs.
        guard constantTimeEquals(Data(tag), expected) else { return nil }

        var plain = Data(count: body.count)
        let keystream = stream.dropFirst(32)
        for index in 0..<body.count {
            plain[index] = body[body.startIndex + index] ^ keystream[keystream.startIndex + index]
        }
        return plain
    }

    /// `crypto_box_afternm`.
    static func seal(_ message: Data, nonce: Data, sharedKey key: Data) -> Data {
        let stream = xsalsa20(key: key, nonce: nonce, count: message.count + 32)
        let keystream = stream.dropFirst(32)
        var body = Data(count: message.count)
        for index in 0..<message.count {
            body[index] = message[message.startIndex + index]
                ^ keystream[keystream.startIndex + index]
        }
        return poly1305(message: body, key: stream.prefix(32)) + body
    }

    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[lhs.startIndex + index] ^ rhs[rhs.startIndex + index]
        }
        return difference == 0
    }

    // MARK: Salsa20

    private static let sigma: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]

    private static func rotl(_ value: UInt32, _ bits: UInt32) -> UInt32 {
        (value << bits) | (value >> (32 - bits))
    }

    /// The 20-round core, shared by Salsa20 and HSalsa20.
    private static func rounds(_ state: inout [UInt32]) {
        for _ in 0..<10 {
            state[4] ^= rotl(state[0] &+ state[12], 7)
            state[8] ^= rotl(state[4] &+ state[0], 9)
            state[12] ^= rotl(state[8] &+ state[4], 13)
            state[0] ^= rotl(state[12] &+ state[8], 18)
            state[9] ^= rotl(state[5] &+ state[1], 7)
            state[13] ^= rotl(state[9] &+ state[5], 9)
            state[1] ^= rotl(state[13] &+ state[9], 13)
            state[5] ^= rotl(state[1] &+ state[13], 18)
            state[14] ^= rotl(state[10] &+ state[6], 7)
            state[2] ^= rotl(state[14] &+ state[10], 9)
            state[6] ^= rotl(state[2] &+ state[14], 13)
            state[10] ^= rotl(state[6] &+ state[2], 18)
            state[3] ^= rotl(state[15] &+ state[11], 7)
            state[7] ^= rotl(state[3] &+ state[15], 9)
            state[11] ^= rotl(state[7] &+ state[3], 13)
            state[15] ^= rotl(state[11] &+ state[7], 18)

            state[1] ^= rotl(state[0] &+ state[3], 7)
            state[2] ^= rotl(state[1] &+ state[0], 9)
            state[3] ^= rotl(state[2] &+ state[1], 13)
            state[0] ^= rotl(state[3] &+ state[2], 18)
            state[6] ^= rotl(state[5] &+ state[4], 7)
            state[7] ^= rotl(state[6] &+ state[5], 9)
            state[4] ^= rotl(state[7] &+ state[6], 13)
            state[5] ^= rotl(state[4] &+ state[7], 18)
            state[11] ^= rotl(state[10] &+ state[9], 7)
            state[8] ^= rotl(state[11] &+ state[10], 9)
            state[9] ^= rotl(state[8] &+ state[11], 13)
            state[10] ^= rotl(state[9] &+ state[8], 18)
            state[12] ^= rotl(state[15] &+ state[14], 7)
            state[13] ^= rotl(state[12] &+ state[15], 9)
            state[14] ^= rotl(state[13] &+ state[12], 13)
            state[15] ^= rotl(state[14] &+ state[13], 18)
        }
    }

    private static func word(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16
            | UInt32(data[base + 3]) << 24
    }

    private static func bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    /// HSalsa20: the core with no feed-forward, used to derive a subkey.
    static func hsalsa20(key: Data, input: Data) -> Data {
        var state: [UInt32] = [
            sigma[0], word(key, 0), word(key, 4), word(key, 8),
            word(key, 12), sigma[1], word(input, 0), word(input, 4),
            word(input, 8), word(input, 12), sigma[2], word(key, 16),
            word(key, 20), word(key, 24), word(key, 28), sigma[3],
        ]
        rounds(&state)
        var out = [UInt8]()
        for index in [0, 5, 10, 15, 6, 7, 8, 9] {
            out.append(contentsOf: bytes(state[index]))
        }
        return Data(out)
    }

    /// The XSalsa20 keystream: HSalsa20 over the first 16 nonce bytes, then Salsa20 with
    /// the remaining 8 and a 64-bit block counter.
    static func xsalsa20(key: Data, nonce: Data, count: Int) -> Data {
        let subkey = hsalsa20(key: key, input: nonce.prefix(16))
        let tail = Data(nonce.suffix(8))
        var out = Data()
        out.reserveCapacity(count)
        var counter: UInt64 = 0
        while out.count < count {
            var state: [UInt32] = [
                sigma[0], word(subkey, 0), word(subkey, 4), word(subkey, 8),
                word(subkey, 12), sigma[1], word(tail, 0), word(tail, 4),
                UInt32(truncatingIfNeeded: counter), UInt32(truncatingIfNeeded: counter >> 32),
                sigma[2], word(subkey, 16),
                word(subkey, 20), word(subkey, 24), word(subkey, 28), sigma[3],
            ]
            let initial = state
            rounds(&state)
            for index in 0..<16 {
                out.append(contentsOf: bytes(state[index] &+ initial[index]))
            }
            counter &+= 1
        }
        return out.prefix(count)
    }

    // MARK: Poly1305

    /// The one-time authenticator, in 26-bit limbs so products fit in 64 bits.
    static func poly1305(message: Data, key: Data) -> Data {
        let key = Data(key)
        var r = [UInt32](repeating: 0, count: 5)
        r[0] = (word(key, 0)) & 0x3FF_FFFF
        r[1] = ((word(key, 3)) >> 2) & 0x3FF_FF03
        r[2] = ((word(key, 6)) >> 4) & 0x3FF_C0FF
        r[3] = ((word(key, 9)) >> 6) & 0x3F0_3FFF
        r[4] = ((word(key, 12)) >> 8) & 0x00F_FFFF

        let pad = [word(key, 16), word(key, 20), word(key, 24), word(key, 28)]
        var h = [UInt32](repeating: 0, count: 5)

        var offset = 0
        let total = message.count
        while offset < total {
            let size = min(16, total - offset)
            var block = Data(message[message.startIndex + offset ..< message.startIndex + offset + size])
            block.append(1)                                   // the "1" bit after the block
            while block.count < 17 { block.append(0) }

            h[0] &+= word(block, 0) & 0x3FF_FFFF
            h[1] &+= (word(block, 3) >> 2) & 0x3FF_FFFF
            h[2] &+= (word(block, 6) >> 4) & 0x3FF_FFFF
            h[3] &+= (word(block, 9) >> 6) & 0x3FF_FFFF
            h[4] &+= (word(block, 12) >> 8) | (UInt32(block[block.startIndex + 16]) << 24)

            // h *= r  (mod 2^130 - 5)
            var d = [UInt64](repeating: 0, count: 5)
            // s[k] = r[k] * 5: the reduction term for a limb that wrapped past 2^130.
            let s: [UInt32] = [0, r[1] &* 5, r[2] &* 5, r[3] &* 5, r[4] &* 5]
            for i in 0..<5 {
                var sum: UInt64 = 0
                for j in 0..<5 {
                    let factor = j <= i ? UInt64(r[i - j]) : UInt64(s[5 + i - j])
                    sum &+= UInt64(h[j]) &* factor
                }
                d[i] = sum
            }
            var carry: UInt64 = 0
            for i in 0..<5 {
                let value = d[i] &+ carry
                h[i] = UInt32(value & 0x3FF_FFFF)
                carry = value >> 26
            }
            h[0] &+= UInt32(carry &* 5)
            h[1] &+= h[0] >> 26
            h[0] &= 0x3FF_FFFF

            offset += size
        }

        // Final carry propagation.
        var carry: UInt32 = 0
        for i in 1..<5 {
            h[i] &+= carry
            carry = h[i] >> 26
            h[i] &= 0x3FF_FFFF
        }
        h[0] &+= carry &* 5
        h[1] &+= h[0] >> 26
        h[0] &= 0x3FF_FFFF

        // g = h + 5 - 2^130, i.e. h - p. The top limb is deliberately left unmasked: its
        // sign bit is what says whether the subtraction borrowed, and masking it first
        // would make every h look smaller than p.
        var g = [UInt32](repeating: 0, count: 5)
        var extra: UInt32 = 5
        for i in 0..<4 {
            let value = UInt64(h[i]) &+ UInt64(extra)
            g[i] = UInt32(value & 0x3FF_FFFF)
            extra = UInt32(value >> 26)
        }
        let top = (h[4] &+ extra) &- (1 << 26)
        // No borrow means h was at least p, so the reduced value is the answer.
        if (top >> 31) == 0 {
            h = [g[0], g[1], g[2], g[3], top]
        }

        // Serialise as four 32-bit words, plus the key's pad.
        var f: UInt64 = 0
        var out = [UInt8]()
        let words = [
            (h[0] | (h[1] << 26)),
            ((h[1] >> 6) | (h[2] << 20)),
            ((h[2] >> 12) | (h[3] << 14)),
            ((h[3] >> 18) | (h[4] << 8)),
        ]
        for i in 0..<4 {
            f = UInt64(words[i]) &+ UInt64(pad[i]) &+ f
            out.append(contentsOf: bytes(UInt32(truncatingIfNeeded: f)))
            f >>= 32
        }
        return Data(out)
    }
}
