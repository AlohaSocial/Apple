// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The initials of an account on a colour of its own.
///
/// Stands in for an avatar that has not loaded, or that does not exist. An
/// empty grey circle on every row of every screen was the single most visible
/// flaw in the app; Nextcloud generates exactly this server-side, so a person
/// with no picture still reads as a person here.
public struct MonogramView: View {
    private let account: Account
    private let size: Double

    public init(account: Account, size: Double) {
        self.account = account
        self.size = size
    }

    public var body: some View {
        // Two stops of the same hue: flat fill at this size looks like a bug,
        // a gradient looks deliberate.
        LinearGradient(
            colors: [
                Monogram.colour(for: seed, lightness: 0.52),
                Monogram.colour(for: seed, lightness: 0.38),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(Monogram.initials(for: account))
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(size * 0.12)
        }
    }

    /// The handle, not the display name: it is the part that does not change,
    /// so somebody's colour stays theirs when they rename themselves.
    private var seed: String { account.acct.isEmpty ? account.id : account.acct }
}

public enum Monogram {
    /// At most two letters, taken from the display name where there is one.
    public static func initials(for account: Account) -> String {
        let source = account.displayName.isEmpty ? account.username : account.displayName
        let words =
            source
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "." })
            .prefix(2)
        let letters = words.compactMap { $0.first(where: \.isLetter) ?? $0.first }
        if letters.isEmpty {
            return String((account.acct.first ?? "?").uppercased())
        }
        return letters.map { String($0).uppercased() }.joined()
    }

    /// A stable hue per handle, in degrees. FNV-1a rather than `hashValue`,
    /// which is seeded per launch and would give somebody a new colour every
    /// time.
    public static func hue(for seed: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Double(hash % 360)
    }

    public static func colour(for seed: String, lightness: Double) -> Color {
        let hue = hue(for: seed) / 360
        // Saturation stays in a narrow band so no avatar screams next to the
        // accent colour, and the two lightnesses keep white text legible.
        return Color(hue: hue, saturation: 0.52, brightness: lightness + 0.28)
    }
}
