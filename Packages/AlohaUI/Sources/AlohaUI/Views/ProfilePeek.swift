// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import SwiftUI

extension View {
    /// On the Mac, resting the pointer on a face shows who it is: banner,
    /// name, a few lines about them and their numbers, without leaving the
    /// timeline. Nothing on the platforms without a pointer that rests.
    @ViewBuilder
    func profilePeek(_ account: Account, onOpen: @escaping () -> Void) -> some View {
        #if os(macOS)
            modifier(ProfilePeek(account: account, onOpen: onOpen))
        #else
            self
        #endif
    }
}

#if os(macOS)
    private struct ProfilePeek: ViewModifier {
        let account: Account
        let onOpen: () -> Void

        @State private var isShown = false
        @State private var isOverAnchor = false
        @State private var isOverCard = false
        @State private var pending: Task<Void, Never>?

        func body(content: Content) -> some View {
            content
                .onHover { isOver in
                    isOverAnchor = isOver
                    settle()
                }
                .popover(isPresented: $isShown, arrowEdge: .leading) {
                    ProfilePeekCard(account: account) {
                        isShown = false
                        onOpen()
                    }
                    .onHover { isOver in
                        isOverCard = isOver
                        settle()
                    }
                }
                .onDisappear { pending?.cancel() }
        }

        /// Shown after the pointer has rested, not as it passes over on the
        /// way down a timeline; put away a moment after it has left both the
        /// face and the card, so the gap between them can be crossed.
        private func settle() {
            pending?.cancel()
            let wanted = isOverAnchor || isOverCard
            guard wanted != isShown else { return }
            pending = Task {
                try? await Task.sleep(for: .milliseconds(wanted ? 650 : 280))
                guard !Task.isCancelled else { return }
                isShown = isOverAnchor || isOverCard
            }
        }
    }

    private struct ProfilePeekCard: View {
        @Environment(\.alohaPalette) private var palette

        let account: Account
        let onOpen: () -> Void

        @State private var about: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: account.preferredHeaderURL) {
                    LinearGradient(
                        colors: [
                            Monogram.colour(for: account.acct, lightness: 0.46),
                            Monogram.colour(for: account.acct, lightness: 0.30),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(width: 320, height: 84)
                .clipped()

                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    HStack(alignment: .bottom, spacing: AlohaMetrics.space3) {
                        AvatarView(account: account, size: 56)
                            .overlay(Circle().strokeBorder(palette.background, lineWidth: 3))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: account.bestDisplayName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(verbatim: "@" + account.acct)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, -24)

                    if let about, !about.isEmpty {
                        Text(verbatim: about)
                            .font(.callout)
                            .foregroundStyle(palette.label)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: AlohaMetrics.space4) {
                        count(account.statusesCount, Text("Posts", comment: "Profile count"))
                        count(account.followingCount, Text("Following", comment: "Profile count"))
                        count(account.followersCount, Text("Followers", comment: "Profile count"))
                    }
                    .font(.caption)

                    Button(action: onOpen) {
                        Text("Open profile", comment: "Profile hover card action")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(AlohaMetrics.space3)
            }
            .frame(width: 320)
            .task(id: account.id) {
                about = await RichTextCache.shared.plainText(
                    for: Status(id: "peek-\(account.id)", content: account.note, account: account)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        private func count(_ value: Int, _ label: Text) -> some View {
            HStack(spacing: 3) {
                Text(value, format: .number.notation(.compactName)).fontWeight(.semibold)
                label.foregroundStyle(palette.secondaryLabel)
            }
        }
    }
#endif
