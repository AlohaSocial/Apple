// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import AlohaUI

@Suite("Statistics number formatting")
struct StatisticsNumbersTests {
    @Test("Invalid server counts are not shown as zero")
    func invalidCounts() {
        for value in [Double.nan, .infinity, -.infinity, -1] {
            #expect(StatisticsNumbers.count(value) == "—")
            #expect(StatisticsNumbers.count(value, compact: true) == "—")
        }
    }

    @Test("Large finite counts format without overflowing Int")
    func largeCounts() {
        for value in [Double(Int.max), 1e30, Double.greatestFiniteMagnitude] {
            #expect(!StatisticsNumbers.count(value).isEmpty)
            #expect(StatisticsNumbers.count(value) != "—")
        }
        #expect(StatisticsNumbers.count(1234.9, locale: Locale(identifier: "en_US")) == "1,234")
        #expect(StatisticsNumbers.count(0, locale: Locale(identifier: "en_US")) == "0")
    }
}
