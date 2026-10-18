import Foundation

/// An amount of aUSD held as integer base units.
///
/// SPEC §6.1: money is integer base units everywhere, never a float, and the UI
/// converts only for display. 1 aUSD = 1,000,000 base units (6 decimals).
struct Units: Hashable, Comparable, Sendable {
    static let decimals = 6
    static let scale: Int64 = 1_000_000

    /// The integer base units. This is the only stored value.
    let raw: Int64

    init(raw: Int64) {
        self.raw = raw
    }

    /// Whole aUSD plus optional cents, e.g. `Units(150)` or `Units(9, cents: 50)`.
    init(_ whole: Int64, cents: Int64 = 0) {
        raw = whole * Self.scale + cents * (Self.scale / 100)
    }

    static let zero = Units(raw: 0)

    static func < (lhs: Units, rhs: Units) -> Bool { lhs.raw < rhs.raw }
    static func + (lhs: Units, rhs: Units) -> Units { Units(raw: lhs.raw + rhs.raw) }
    static func - (lhs: Units, rhs: Units) -> Units { Units(raw: lhs.raw - rhs.raw) }

    /// "$1,240.00"
    var display: String {
        "$\(Self.grouped(raw / Self.scale)).\(Self.centsText(raw))"
    }

    /// "$1,240" — drops a zero fraction, for tight spots like chips and stats.
    var compact: String {
        let cents = Self.centsText(raw)
        return cents == "00" ? "$\(Self.grouped(raw / Self.scale))" : display
    }

    /// "1,240.00 aUSD" — used where the on-chain token matters more than the figure.
    var token: String {
        "\(Self.grouped(raw / Self.scale)).\(Self.centsText(raw)) aUSD"
    }

    /// Share of a total, for progress bars only — never for money arithmetic.
    func fraction(of total: Units) -> Double {
        guard total.raw > 0 else { return 0 }
        return min(1, max(0, Double(raw) / Double(total.raw)))
    }

    private static let groupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func grouped(_ whole: Int64) -> String {
        groupingFormatter.string(from: NSNumber(value: whole)) ?? String(whole)
    }

    private static func centsText(_ raw: Int64) -> String {
        let cents = abs(raw % scale) / (scale / 100)
        return cents < 10 ? "0\(cents)" : String(cents)
    }
}

extension Units: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int64) {
        self.init(value)
    }
}
