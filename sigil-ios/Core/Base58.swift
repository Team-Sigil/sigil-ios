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
        let leadingOnes = string.prefix { $0 == "1" }.count
        return Array(repeating: 0, count: leadingOnes) + bytes.reversed()
    }
}
