// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation
import OSLog

#if canImport(BackgroundTasks)
    import BackgroundTasks
#endif

/// `BGAppRefreshTask` and `BGProcessingTask` registration (docs/08 §4).
public enum BackgroundWork {
    public static let refreshIdentifier = "com.nextcloud.alohasocial.refresh"
    public static let maintenanceIdentifier = "com.nextcloud.alohasocial.maintenance"

    /// A hard budget. The expiration handler cancels in-flight work and saves
    /// what it has rather than being killed mid-write.
    public static let refreshBudget: TimeInterval = 25

    private static let logger = Logger(
        subsystem: "com.nextcloud.alohasocial", category: "background")

    @MainActor
    public static func register(environment: AppEnvironment) {
        #if os(iOS) || os(visionOS)
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: refreshIdentifier, using: nil
            ) { task in
                guard let task = task as? BGAppRefreshTask else { return }
                handleRefresh(task, environment: environment)
            }

            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: maintenanceIdentifier, using: nil
            ) { task in
                guard let task = task as? BGProcessingTask else { return }
                handleMaintenance(task, environment: environment)
            }
        #endif
    }

    @MainActor
    public static func scheduleRefresh(after interval: TimeInterval = 900) {
        #if os(iOS) || os(visionOS)
            let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
            request.earliestBeginDate = Date().addingTimeInterval(interval)
            // `submitTaskRequest` rather than the deprecated `submit`: it is
            // the one that reports every refusal, and a refusal here is worth
            // a line in the log rather than a silent dead chain.
            Task { @MainActor in await submit(request) }
        #endif
    }

    @MainActor
    public static func scheduleMaintenance() {
        #if os(iOS) || os(visionOS)
            let request = BGProcessingTaskRequest(identifier: maintenanceIdentifier)
            // Sweeping and image eviction are not worth a person's battery.
            request.requiresExternalPower = true
            request.requiresNetworkConnectivity = false
            request.earliestBeginDate = Date().addingTimeInterval(3600 * 6)
            Task { @MainActor in await submit(request) }
        #endif
    }

    #if os(iOS) || os(visionOS)
        /// `@MainActor` so the request never leaves the actor it was built on:
        /// `BGTaskRequest` is not `Sendable`, and handing one to a detached
        /// task is a data race the compiler is right to refuse.
        @MainActor
        private static func submit(_ request: BGTaskRequest) async {
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                // Not fatal: the app still refreshes when it is opened. Worth
                // saying, because a simulator and an unentitled build both
                // refuse here and the silence used to look like success.
                logger.notice(
                    "background task not scheduled: \(String(describing: error), privacy: .public)")
            }
        }
    #endif

    #if os(iOS) || os(visionOS)
        @MainActor
        private static func handleRefresh(_ task: BGAppRefreshTask, environment: AppEnvironment) {
            // Re-submitted at the end of every run, so the chain never breaks.
            scheduleRefresh()

            let work = Task {
                _ = await environment.performBackgroundRefresh()
                WidgetReloader.reloadAll()
                task.setTaskCompleted(success: true)
            }

            task.expirationHandler = {
                logger.notice("background refresh expired; cancelling in flight work")
                work.cancel()
            }
        }

        @MainActor
        private static func handleMaintenance(
            _ task: BGProcessingTask, environment: AppEnvironment
        ) {
            scheduleMaintenance()

            let work = Task {
                await environment.sweepCaches()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    #endif
}

#if canImport(WidgetKit)
    import WidgetKit
#endif

public enum WidgetReloader {
    public static func reloadAll() {
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
