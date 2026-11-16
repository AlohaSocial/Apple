// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

#if os(macOS)
    extension ComposerView {
        /// Who is writing and who will read it, above the words: the face and
        /// name of the account, and the audience as a chip that says what it
        /// is rather than a globe among the tools.
        var macHeader: some View {
            HStack(spacing: AlohaMetrics.space3) {
                AvatarView(account: model.session.snapshot.asAccount, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: model.session.snapshot.bestDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: model.session.snapshot.qualifiedHandle)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: AlohaMetrics.space2)
                Menu {
                    Picker(selection: $model.visibility) {
                        Text("Public", comment: "Visibility").tag(Visibility.public)
                        Text("Unlisted", comment: "Visibility").tag(Visibility.unlisted)
                        Text("Followers only", comment: "Visibility").tag(Visibility.private)
                        Text("Direct", comment: "Visibility").tag(Visibility.direct)
                    } label: {
                        Text("Visibility", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        audienceTitle
                    } icon: {
                        Image(systemName: model.visibilitySymbol)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, AlohaMetrics.space2)
                    .padding(.vertical, 5)
                    .background(palette.accent.opacity(0.16), in: Capsule())
                    .foregroundStyle(palette.accent)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .help(Text("Who can see this", comment: "Composer action"))
            }
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.top, AlohaMetrics.space3)
        }

        private var audienceTitle: Text {
            switch model.visibility {
            case .public: Text("Public", comment: "Visibility")
            case .unlisted: Text("Unlisted", comment: "Visibility")
            case .private: Text("Followers only", comment: "Visibility")
            case .direct: Text("Direct", comment: "Visibility")
            default: Text("Visibility", comment: "Composer picker")
            }
        }

        /// The post as a timeline will show it, under the editor: what a
        /// link, a mention or a line break turns into, before it is sent.
        var macPreview: some View {
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                Text("Preview", comment: "Composer preview heading")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .textCase(.uppercase)
                StatusRow(
                    status: Status(
                        id: "composer-preview", content: Self.html(model.text),
                        account: model.session.snapshot.asAccount),
                    policy: model.session.settings.sensitiveMediaPolicy,
                    localHost: model.session.snapshot.instanceHost,
                    showActions: false, showsTimestamp: false, showsOwnMarker: false
                ) { _ in }
                .allowsHitTesting(false)
            }
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.bottom, AlohaMetrics.space2)
            .transition(.opacity)
        }

        /// The typed words as the HTML a server would return for them:
        /// escaped, a paragraph for each blank-line break, a line break for
        /// each single one.
        nonisolated static func html(_ text: String) -> String {
            let escaped =
                text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return
                escaped
                .components(separatedBy: "\n\n")
                .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
                .joined()
        }
    }

    /// How much of the post's length is used, as a ring that fills, with the
    /// number inside once it matters.
    struct CharacterRing: View {
        @Environment(\.alohaPalette) private var palette

        let remaining: Int
        let limit: Int

        var body: some View {
            let used = limit > 0 ? Double(limit - remaining) / Double(limit) : 0
            let colour =
                remaining < 0 ? palette.destructive : (remaining < 20 ? .orange : palette.accent)
            return HStack(spacing: AlohaMetrics.space2) {
                if remaining < 50 {
                    Text(remaining, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            remaining < 0 ? palette.destructive : palette.secondaryLabel)
                }
                ZStack {
                    Circle().stroke(palette.separator.opacity(0.6), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: min(max(used, 0), 1))
                        .stroke(colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                .animation(.easeOut(duration: 0.15), value: used)
            }
            .help(
                Text(
                    "^[\(remaining) character](inflect: true) left",
                    comment: "Composer counter"))
        }
    }
#endif
