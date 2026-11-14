// SPDX-License-Identifier: MIT

import Foundation
import Network
import Observation

/// What the device's network path says, as the poller needs it: whether
/// there is a network at all, and whether it is one that costs (docs/08 §3).
///
/// Observable, so a poll loop paused for want of a network resumes on the
/// path update itself rather than on a timer that guesses when to look.
@MainActor
@Observable
public final class NetworkConditions {
    /// Assumed until the first path update says otherwise: pausing on a
    /// guess would hold the first poll back for nothing.
    public private(set) var isSatisfied = true
    /// Cellular, or a network the system marks expensive — a personal
    /// hotspot is Wi-Fi to the device and a data plan to the person.
    public private(set) var isCellular = false

    @ObservationIgnored private var monitor: NWPathMonitor?
    /// Set by a test that states the conditions itself; the device's own
    /// path updates are then ignored.
    @ObservationIgnored private var isSimulated = false

    public init() {}

    /// Starts listening to the path. Once is enough for the process: the
    /// monitor is cheap, and the first update after a start is what tells a
    /// poll loop it may go.
    func startMonitoring() {
        guard monitor == nil, !isSimulated else { return }
        let monitor = NWPathMonitor()
        // `@Sendable`: the monitor calls it on its own queue, and a closure
        // isolated to the main actor called there traps (IsolationTests).
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let satisfied = path.status == .satisfied
            let cellular = path.usesInterfaceType(.cellular) || path.isExpensive
            Task { @MainActor in self?.apply(isSatisfied: satisfied, isCellular: cellular) }
        }
        monitor.start(queue: DispatchQueue(label: "social.aloha.app.network-path"))
        self.monitor = monitor
    }

    /// For tests: the conditions as stated, whatever the device's path is.
    func simulate(isSatisfied: Bool, isCellular: Bool = false) {
        isSimulated = true
        monitor?.cancel()
        monitor = nil
        set(isSatisfied: isSatisfied, isCellular: isCellular)
    }

    private func apply(isSatisfied: Bool, isCellular: Bool) {
        guard !isSimulated else { return }
        set(isSatisfied: isSatisfied, isCellular: isCellular)
    }

    /// Written only on a change, so an update that says what was already
    /// known does not wake every paused loop.
    private func set(isSatisfied: Bool, isCellular: Bool) {
        if self.isSatisfied != isSatisfied { self.isSatisfied = isSatisfied }
        if self.isCellular != isCellular { self.isCellular = isCellular }
    }
}
