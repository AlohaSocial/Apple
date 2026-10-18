// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

extension AccountSession {
    /// The waits between checks for a pending follow's Accept. A server that
    /// accepts by itself usually has by the first.
    static let followAcceptChecks: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]

    /// Asks again for a follow of an open account that the follow reply left
    /// pending, until the other server's Accept has landed or the checks run
    /// out. Each fresh relationship goes to `update`.
    @MainActor
    func settleFollow(
        _ relationship: Relationship, locked: Bool,
        waits: [Duration] = followAcceptChecks,
        update: (Relationship) -> Void
    ) async {
        guard relationship.awaitsAutomaticAccept(locked: locked) else { return }
        for wait in waits {
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            guard
                let current = try? await client.decode(
                    LossyArray<Relationship>.self,
                    from: Endpoint.accounts.relationships([relationship.id])
                ).elements.first
            else { continue }
            update(current)
            if !current.awaitsAutomaticAccept(locked: locked) { return }
        }
    }
}
