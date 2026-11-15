// SPDX-License-Identifier: MIT

import SwiftUI

#if os(iOS)
    /// The off switch for the poll and scheduled-post countdowns (docs/09 §9).
    ///
    /// A device setting rather than an account's: the Lock Screen is one
    /// place, whichever account is active. When the system has Live
    /// Activities turned off for the app, the switch says so instead of
    /// pretending to work.
    struct LiveActivitySettingsSection: View {
        @Environment(AppEnvironment.self) private var environment
        @AppStorage(EventLiveActivities.enabledKey) private var isEnabled = true

        var body: some View {
            Section {
                Toggle(isOn: $isEnabled) {
                    Text(
                        "Count down to my polls and scheduled posts",
                        comment: "Settings switch for the poll and scheduled post Live Activities")
                }
                .disabled(!EventLiveActivities.areSystemActivitiesEnabled)
                .onChange(of: isEnabled) { _, enabled in
                    Task {
                        if enabled {
                            await EventLiveActivities.update(environment)
                        } else {
                            await EventLiveActivities.endAll()
                        }
                    }
                }
            } header: {
                Text("Live Activities", comment: "Settings section")
            } footer: {
                if EventLiveActivities.areSystemActivitiesEnabled {
                    Text(
                        "When your poll closes or your next scheduled post goes out within the hour, a countdown appears on the Lock Screen and in the Dynamic Island.",
                        comment: "Explanation of the poll and scheduled post Live Activities")
                } else {
                    Text(
                        "Live Activities are turned off for Aloha Social. You can turn them on in the Settings app, under Aloha Social.",
                        comment: "Shown when the system has Live Activities turned off for the app")
                }
            }
        }
    }
#endif
