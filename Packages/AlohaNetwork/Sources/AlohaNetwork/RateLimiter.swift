// SPDX-License-Identifier: MIT

import Foundation

/// A per-host token bucket, shared across accounts on the same host.
///
/// Five accounts on one small instance should behave like one (docs/08 §3).
/// Several Nextcloud Social routes are rate-limited per anonymous caller —
/// `/api/oembed`, `/instance/peers`, `/instance/activity`, media uploads,
/// `/media/playlist/*`, and the OAuth token and revoke endpoints.
public actor RateLimiter {
    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
        /// Set by a 429. Nothing goes out to this host until it passes.
        var blockedUntil: Date?
    }

    private var buckets: [String: Bucket] = [:]
    private let capacity: Double
    private let refillPerSecond: Double
    private let clock: @Sendable () -> Date

    public init(
        capacity: Double = 30,
        refillPerSecond: Double = 3,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.clock = clock
    }

    /// Waits until this host will accept another request.
    ///
    /// Throws `.cancelled` when the waiting task is cancelled — a `.task` that
    /// went away, a background task that expired — rather than going on
    /// waiting for a slot nobody wants. A host that answered 429 with a long
    /// `Retry-After` fails at once with `.rateLimited` instead of holding the
    /// request, and whoever asked can say so and offer to try later.
    public func acquire(host: String, maximumBlockedWait: TimeInterval = 10) async throws {
        while true {
            if Task.isCancelled { throw APIError.cancelled }
            let (wait, blocked) = reserve(host: host)
            guard wait > 0 else { return }
            if blocked, wait > maximumBlockedWait { throw APIError.rateLimited(retryAfter: wait) }
            do {
                try await Task.sleep(for: .seconds(min(wait, 60)))
            } catch {
                throw APIError.cancelled
            }
        }
    }

    /// How long to wait before a request may go, and whether that wait is a
    /// 429 block rather than the bucket refilling.
    private func reserve(host: String) -> (wait: TimeInterval, blocked: Bool) {
        let now = clock()
        var bucket = buckets[host] ?? Bucket(tokens: capacity, lastRefill: now, blockedUntil: nil)

        if let blockedUntil = bucket.blockedUntil {
            if blockedUntil > now {
                buckets[host] = bucket
                return (blockedUntil.timeIntervalSince(now), true)
            }
            bucket.blockedUntil = nil
        }

        let elapsed = now.timeIntervalSince(bucket.lastRefill)
        bucket.tokens = min(capacity, bucket.tokens + elapsed * refillPerSecond)
        bucket.lastRefill = now

        if bucket.tokens >= 1 {
            bucket.tokens -= 1
            buckets[host] = bucket
            return (0, false)
        }

        buckets[host] = bucket
        return ((1 - bucket.tokens) / refillPerSecond, false)
    }

    /// Honour `Retry-After` where the server sent one; back off with jitter
    /// where it did not.
    public func noteRateLimited(host: String, retryAfter: TimeInterval?) {
        let now = clock()
        let delay = retryAfter ?? Double.random(in: 20...60)
        var bucket = buckets[host] ?? Bucket(tokens: 0, lastRefill: now, blockedUntil: nil)
        bucket.tokens = 0
        bucket.blockedUntil = now.addingTimeInterval(delay)
        buckets[host] = bucket
    }

    public func isBlocked(host: String) -> Bool {
        guard let blockedUntil = buckets[host]?.blockedUntil else { return false }
        return blockedUntil > clock()
    }
}

/// Exponential backoff with full jitter, capped. Used for retries and for the
/// poll scheduler's failure path.
public enum Backoff {
    public static func delay(
        attempt: Int, base: TimeInterval = 1, cap: TimeInterval = 900
    ) -> TimeInterval {
        let exponential = min(cap, base * pow(2, Double(max(0, attempt))))
        return Double.random(in: 0...exponential)
    }
}
