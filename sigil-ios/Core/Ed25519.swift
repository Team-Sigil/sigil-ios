import Foundation

/// Just enough ed25519 field arithmetic to answer one question: is this 32-byte value a
/// point on the curve?
///
/// Solana's `findProgramAddress` hashes seeds with a decreasing bump until the result is
/// **off** the curve — that is what makes a program-derived address one that nobody holds
/// a key for. Getting this wrong silently yields a different address, which is why it is
/// checked against known associated token accounts.
///
/// These are public values, so the arithmetic is plain rather than constant-time.
enum Ed25519 {
    /// Eight 32-bit limbs, least significant first: a 256-bit number mod 2^255 - 19.
    private typealias Field = [UInt32]

    private static let limbs = 8

    /// p = 2^255 - 19
    private static let p: Field = [
        0xFFFF_FFED, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF,
        0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x7FFF_FFFF,
    ]

    static func isOnCurve(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 32 else { return false }

        // y is the value with the sign bit stripped; the top bit is x's sign.
        var yBytes = bytes
        let sign = (yBytes[31] >> 7) & 1
        yBytes[31] &= 0x7F
        let y = field(from: yBytes)
        guard less(y, p) else { return false }

        // The curve: -x^2 + y^2 = 1 + d·x^2·y^2, so x^2 = (y^2 - 1) / (d·y^2 + 1).
        let yy = mul(y, y)
        let u = sub(yy, one)
        let v = add(mul(d, yy), one)
        let xx = mul(u, inverse(v))

        // A square root exists only if (x^2)^((p+3)/8) squares back to x^2, possibly after
        // multiplying by sqrt(-1).
        var x = power(xx, exponentPPlus3Over8)
        if !equal(mul(x, x), xx) {
            x = mul(x, sqrtMinusOne)
        }
        guard equal(mul(x, x), xx) else { return false }

        // x = 0 with a negative sign is not a valid encoding.
        if isZero(x), sign == 1 { return false }
        return true
    }

    // MARK: Constants

    private static let one: Field = [1, 0, 0, 0, 0, 0, 0, 0]

    /// d = -121665 / 121666
    private static let d: Field = {
        let numerator = sub(p, field(from: 121_665))
        return mul(numerator, inverse(field(from: 121_666)))
    }()

    /// sqrt(-1) = 2^((p-1)/4)
    private static let sqrtMinusOne: Field = power(field(from: 2), exponentPMinus1Over4)

    /// (p + 3) / 8 = 2^252 - 2
    private static let exponentPPlus3Over8: Field = {
        var value = shiftLeftPowerOfTwo(252)
        value = sub(value, field(from: 2))
        return value
    }()

    /// (p - 1) / 4 = 2^253 - 5
    private static let exponentPMinus1Over4: Field = {
        var value = shiftLeftPowerOfTwo(253)
        value = sub(value, field(from: 5))
        return value
    }()

    /// p - 2, the exponent that inverts a field element.
    private static let exponentPMinus2: Field = sub(p, field(from: 2))

    // MARK: Field arithmetic

    private static func field(from value: UInt32) -> Field {
        var out = Field(repeating: 0, count: limbs)
        out[0] = value
        return out
    }

    private static func field(from bytes: [UInt8]) -> Field {
        var out = Field(repeating: 0, count: limbs)
        for index in 0..<limbs {
            let base = index * 4
            out[index] = UInt32(bytes[base])
                | UInt32(bytes[base + 1]) << 8
                | UInt32(bytes[base + 2]) << 16
                | UInt32(bytes[base + 3]) << 24
        }
        return out
    }

    /// 2^exponent, which only ever needs to be below 2^255 here.
    private static func shiftLeftPowerOfTwo(_ exponent: Int) -> Field {
        var out = Field(repeating: 0, count: limbs)
        out[exponent / 32] = UInt32(1) << UInt32(exponent % 32)
        return out
    }

    private static func isZero(_ a: Field) -> Bool {
        a.allSatisfy { $0 == 0 }
    }

    private static func equal(_ a: Field, _ b: Field) -> Bool {
        a == b
    }

    private static func less(_ a: Field, _ b: Field) -> Bool {
        for index in stride(from: limbs - 1, through: 0, by: -1) {
            if a[index] != b[index] { return a[index] < b[index] }
        }
        return false
    }

    private static func add(_ a: Field, _ b: Field) -> Field {
        var out = Field(repeating: 0, count: limbs)
        var carry: UInt64 = 0
        for index in 0..<limbs {
            let sum = UInt64(a[index]) + UInt64(b[index]) + carry
            out[index] = UInt32(truncatingIfNeeded: sum)
            carry = sum >> 32
        }
        // A carry out of the top means one p too many; 2^256 mod p is 38.
        if carry > 0 {
            out = addSmall(out, 38)
        }
        return reduceOnce(out)
    }

    private static func addSmall(_ a: Field, _ value: UInt32) -> Field {
        var out = a
        var carry = UInt64(value)
        for index in 0..<limbs where carry > 0 {
            let sum = UInt64(out[index]) + carry
            out[index] = UInt32(truncatingIfNeeded: sum)
            carry = sum >> 32
        }
        return out
    }

    private static func sub(_ a: Field, _ b: Field) -> Field {
        var out = Field(repeating: 0, count: limbs)
        var borrow: Int64 = 0
        for index in 0..<limbs {
            let difference = Int64(a[index]) - Int64(b[index]) - borrow
            if difference < 0 {
                out[index] = UInt32(truncatingIfNeeded: difference + 0x1_0000_0000)
                borrow = 1
            } else {
                out[index] = UInt32(truncatingIfNeeded: difference)
                borrow = 0
            }
        }
        // Borrowed past the top: add p back.
        if borrow > 0 {
            var carry: UInt64 = 0
            for index in 0..<limbs {
                let sum = UInt64(out[index]) + UInt64(p[index]) + carry
                out[index] = UInt32(truncatingIfNeeded: sum)
                carry = sum >> 32
            }
        }
        return out
    }

    private static func mul(_ a: Field, _ b: Field) -> Field {
        var wide = [UInt64](repeating: 0, count: limbs * 2)
        for i in 0..<limbs {
            var carry: UInt64 = 0
            for j in 0..<limbs {
                let product = UInt64(a[i]) * UInt64(b[j]) + wide[i + j] + carry
                wide[i + j] = product & 0xFFFF_FFFF
                carry = product >> 32
            }
            var index = i + limbs
            while carry > 0 {
                let sum = wide[index] + carry
                wide[index] = sum & 0xFFFF_FFFF
                carry = sum >> 32
                index += 1
            }
        }

        // 2^256 ≡ 38 (mod p), so fold the top half down until nothing is left up there.
        var low = Field(repeating: 0, count: limbs)
        for index in 0..<limbs { low[index] = UInt32(truncatingIfNeeded: wide[index]) }
        var high = Field(repeating: 0, count: limbs)
        for index in 0..<limbs { high[index] = UInt32(truncatingIfNeeded: wide[index + limbs]) }

        var result = low
        if !isZero(high) {
            result = add(result, mulSmall(high, 38))
        }
        return reduceOnce(result)
    }

    /// Multiplies by a small constant, folding any overflow back in with 2^256 ≡ 38.
    private static func mulSmall(_ a: Field, _ value: UInt32) -> Field {
        var out = Field(repeating: 0, count: limbs)
        var carry: UInt64 = 0
        for index in 0..<limbs {
            let product = UInt64(a[index]) * UInt64(value) + carry
            out[index] = UInt32(truncatingIfNeeded: product)
            carry = product >> 32
        }
        if carry > 0 {
            out = addSmall(out, UInt32(truncatingIfNeeded: carry * 38))
        }
        return out
    }

    /// One conditional subtraction of p, which is all an already-folded value needs.
    private static func reduceOnce(_ a: Field) -> Field {
        var out = a
        while !less(out, p) {
            var borrow: Int64 = 0
            var next = Field(repeating: 0, count: limbs)
            for index in 0..<limbs {
                let difference = Int64(out[index]) - Int64(p[index]) - borrow
                if difference < 0 {
                    next[index] = UInt32(truncatingIfNeeded: difference + 0x1_0000_0000)
                    borrow = 1
                } else {
                    next[index] = UInt32(truncatingIfNeeded: difference)
                    borrow = 0
                }
            }
            out = next
        }
        return out
    }

    private static func power(_ base: Field, _ exponent: Field) -> Field {
        var result = one
        var factor = base
        for limb in 0..<limbs {
            for bit in 0..<32 {
                if (exponent[limb] >> UInt32(bit)) & 1 == 1 {
                    result = mul(result, factor)
                }
                factor = mul(factor, factor)
            }
        }
        return result
    }

    private static func inverse(_ a: Field) -> Field {
        power(a, exponentPMinus2)
    }
}
