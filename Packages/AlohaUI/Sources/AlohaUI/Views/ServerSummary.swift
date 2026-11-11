// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// What a server says about itself, shown before a person commits to it.
///
/// The introduction and the sign-in sheet both need this: one has just found
/// the server, the other is opening for an account that was added later.
struct ServerSummary: View {
    @Environment(\.alohaPalette) private var palette

    let instance: InstanceDescription

    var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                RemoteImage(url: instance.thumbnail)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))

                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.title)
                        .font(.headline)
                        .accessibilityIdentifier("server-found-title")
                    Text(instance.domain)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    serverStats
                    serverDetails
                }

                Spacer(minLength: 0)
            }

            if !instance.shortDescription.isEmpty {
                Text(instance.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// People, posts and connected servers as one line of facts — each only
    /// where the server answered it.
    @ViewBuilder
    private var serverStats: some View {
        let stats: [Text] = [
            instance.userCount.map {
                Text("^[\($0) person](inflect: true)", comment: "Instance user count")
            },
            instance.statusCount.map {
                Text("^[\($0) post](inflect: true)", comment: "Instance post count")
            },
            instance.domainCount.map {
                Text(
                    "^[\($0) connected server](inflect: true)",
                    comment: "Instance server count")
            },
        ].compactMap { $0 }
        if !stats.isEmpty {
            // One Text from many, so the line wraps as a unit, and the
            // separators join without a trailing one.
            Text.concatenating(
                stats.dropFirst().reduce([stats[0]]) { $0 + [Text(verbatim: " · "), $1] }
            )
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
        }
    }

    /// Version, registration state and languages: the three things that tell
    /// a person whether this server takes new accounts and speaks theirs.
    private var serverDetails: Text {
        var parts: [String] = []
        if !instance.version.isEmpty { parts.append(instance.version) }
        if instance.registrationsEnabled {
            parts.append(
                instance.approvalRequired
                    ? String(
                        localized: "Registrations open, approval required",
                        comment: "Instance detail")
                    : String(localized: "Registrations open", comment: "Instance detail"))
        } else {
            parts.append(String(localized: "Registrations closed", comment: "Instance detail"))
        }
        if !instance.languages.isEmpty {
            parts.append(instance.languages.joined(separator: ", ").uppercased())
        }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
    }
}
