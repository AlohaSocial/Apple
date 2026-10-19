// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation

// The settings Aloha Social keeps on the server as well as here. The server is
// the truth: it applies them to every answer it gives (hidden counts arrive as
// zeros) and to every notification it delivers, on every device. So they are
// read from it whenever the session refreshes, and written to it whenever the
// reader changes one here.

extension AccountSession {
    /// Reads the server's counts and notification delivery into this
    /// account's settings. A server that does not answer leaves them alone.
    func adoptServerReaderSettings() async {
        if let counts = try? await client.decode(HideSetting.self, from: .readerSettings.counts) {
            // Hidden counts arrive as 0 on every post (`HideCountsMiddleware`),
            // and a row of zeros says something false. Showing no numbers is
            // what the server's own setting means.
            if settings.showPopularityCounts == counts.hide {
                await updateSettings { $0.showPopularityCounts = !counts.hide }
            }
        }
        if let delivery = try? await client.decode(
            NotificationDeliverySettings.self, from: .readerSettings.notificationDelivery)
        {
            serverNotificationDelivery = delivery
            var adopted = settings
            adopted.adopt(delivery)
            if adopted != settings {
                await updateSettings { $0.adopt(delivery) }
            }
        }
    }

    /// "Show numbers", here and on the server. Changed here first so the
    /// switch answers at once; put back if the server refuses, because a
    /// switch that says on while every count arrives as 0 is worse than one
    /// that did not move.
    public func setShowsCounts(_ shows: Bool) async {
        let previous = settings.showPopularityCounts
        await updateSettings { $0.showPopularityCounts = shows }
        guard capabilities.isNextcloudSocial else { return }
        do {
            let answer = try await client.decode(
                HideSetting.self, from: .readerSettings.setCounts(hide: !shows))
            if answer.hide == shows {
                await updateSettings { $0.showPopularityCounts = !answer.hide }
            }
        } catch {
            await updateSettings { $0.showPopularityCounts = previous }
            await handle(error)
        }
    }

    /// Sends this account's digest times, delivery mode and quiet hours to the
    /// server, which applies them to the Nextcloud notifications it delivers.
    /// What this app does not edit — the passthrough switches — goes back as
    /// the server last said, read first if it never has been.
    public func pushNotificationDelivery() async {
        guard capabilities.isNextcloudSocial else { return }
        if serverNotificationDelivery == nil {
            serverNotificationDelivery = try? await client.decode(
                NotificationDeliverySettings.self, from: .readerSettings.notificationDelivery)
        }
        let outgoing = settings.serverDelivery(
            keeping: serverNotificationDelivery ?? NotificationDeliverySettings())
        do {
            serverNotificationDelivery = try await client.decode(
                NotificationDeliverySettings.self,
                from: .readerSettings.setNotificationDelivery(outgoing))
        } catch {
            await handle(error)
        }
    }
}

/// A value transform on a store type: no isolation of its own, so the
/// settings closures, which run wherever they are called, can use it.
nonisolated extension AccountSettings {
    /// The server's delivery, in this app's terms: whole hours, at most four
    /// digest times, quiet hours as a start and an end or none at all.
    mutating func adopt(_ delivery: NotificationDeliverySettings) {
        notificationDeliveryMode = delivery.mode == .digest ? .digest : .immediate
        let hours = delivery.times.compactMap(NotificationDeliverySettings.hour(of:))
        // An empty list on the server is its own default; the app's is 08:00.
        if !hours.isEmpty {
            digestTimes = Array(hours.prefix(NotificationDeliverySettings.maximumTimes))
        }
        let from = NotificationDeliverySettings.hour(of: delivery.quietFrom)
        let to = NotificationDeliverySettings.hour(of: delivery.quietTo)
        if let from, let to {
            quietHoursStart = from
            quietHoursEnd = to
        } else {
            quietHoursStart = nil
            quietHoursEnd = nil
        }
    }

    /// This account's delivery as the server writes it, on top of what the
    /// server already holds.
    func serverDelivery(
        keeping server: NotificationDeliverySettings
    ) -> NotificationDeliverySettings {
        var outgoing = server
        outgoing.mode = notificationDeliveryMode == .digest ? .digest : .instant
        let times = digestTimes.isEmpty ? [8] : digestTimes
        outgoing.times = Array(
            times.prefix(NotificationDeliverySettings.maximumTimes)
                .map(NotificationDeliverySettings.wireTime(hour:)))
        if let start = quietHoursStart, let end = quietHoursEnd {
            outgoing.quietFrom = NotificationDeliverySettings.wireTime(hour: start)
            outgoing.quietTo = NotificationDeliverySettings.wireTime(hour: end)
        } else {
            outgoing.quietFrom = ""
            outgoing.quietTo = ""
        }
        return outgoing
    }
}
