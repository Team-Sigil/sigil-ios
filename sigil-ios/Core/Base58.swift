import Foundation

/// Base58 in the alphabet Solana uses for public keys and signatures.
enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }

        // Repeated division of the whole number by 58, kept as base-256 digits.
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for index in digits.indices {
                carry += Int(digits[index]) << 8
                digits[index] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        // Every leading zero byte is one leading "1".
        let leadingZeros = bytes.prefix { $0 == 0 }.count
        let characters = digits.reversed().map { alphabet[Int($0)] }
        return String(repeating: "1", count: leadingZeros) + String(characters)
    }

    static func decode(_ string: String) -> [UInt8]? {
        var bytes: [UInt8] = [0]
        for character in string {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            var carry = value
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        // The accumulator starts at zero, and a small value leaves those zero limbs at
        // the top. They are not part of the number: in base58 a leading zero byte is
        // written as "1", and those are counted separately below.
        while let last = bytes.last, last == 0, bytes.count > 1 {
            bytes.removeLast()
        }
        if bytes == [0] { bytes = [] }
        let leadingOnes = string.prefix { $0 == "1" }.count
        return Array(repeating: 0, count: leadingOnes) + bytes.reversed()
    }

    /// A 32-byte Solana public key is 32..44 base58 characters and nothing else.
    static func isPubkey(_ string: String) -> Bool {
        guard let bytes = decode(string) else { return false }
        return bytes.count == 32
    }
}
