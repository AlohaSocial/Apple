// SPDX-License-Identifier: MIT

import SwiftUI

/// A post's age that keeps itself current: "now" becomes "1m" without the
/// timeline being refreshed.
///
/// The schedule follows `PostAge.refreshInterval`, so a row from last week
/// is not redrawn every minute. The exact time is the tooltip on iPad and
/// Mac, and what VoiceOver reads alongside the relative age.
public struct PostAgeText: View {
    private let date: Date

    public init(_ date: Date) {
        self.date = date
    }

    public var body: some View {
        // SwiftUI's, not the app's own timeline of posts.
        SwiftUI.TimelineView(.periodic(from: date, by: PostAge.refreshInterval(for: date))) {
            context in
            Text(verbatim: PostAge.short(date, now: context.date))
                .accessibilityLabel(Text(verbatim: PostAge.spoken(date, now: context.date)))
        }
        .help(Text(verbatim: PostAge.absolute(date)))
    }
}
