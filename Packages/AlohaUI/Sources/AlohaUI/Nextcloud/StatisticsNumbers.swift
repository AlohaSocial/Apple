// SPDX-License-Identifier: MIT
import Foundation

enum StatisticsNumbers {
    /// Do not convert server-provided doubles to Int: out-of-range values trap.
    /// Missing or invalid counts are not presented as genuine zeroes.
    static func count(_ value: Double, compact: Bool = false, locale: Locale = .current) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        let count = value.rounded(.towardZero)
        if compact {
            return count.formatted(
                .number.notation(.compactName).precision(.fractionLength(0)).locale(locale))
        }
        return count.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}
