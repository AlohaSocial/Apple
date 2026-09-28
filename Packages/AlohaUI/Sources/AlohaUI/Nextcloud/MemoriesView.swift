// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// "Looking back": what you posted on this day in other years, and how this
/// week compares with the last — with the switch that turns the recap on.
public struct MemoriesView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var memories: [Status] = []
    @State private var recap: WeeklyRecap?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
            }

            Section {
                if let recap, recap.enabled {
                    WeeklyRecapSummary(recap: recap)
                }
                Toggle(
                    isOn: Binding(
                        get: { recap?.enabled ?? false },
                        set: { value in Task { await setRecap(enabled: value) } })
                ) {
                    Text("Weekly recap", comment: "Memories setting")
                }
                .disabled(recap == nil)
            } header: {
                Text("This week", comment: "Memories section")
            } footer: {
                Text(
                    "Once a week, a line at the top of your feed says how much you posted against the week before. Counted on your server, shown to you alone.",
                    comment: "Weekly recap explanation")
            }

            Section {
                ForEach(memories) { status in
                    MemoryRow(status: status) { onAction(.open(status)) }
                }

                if memories.isEmpty && !isLoading {
                    Text(
                        "Nothing from this day in earlier years.",
                        comment: "Empty on this day"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
            } header: {
                Text("On this day", comment: "Memories section")
            }
        }
        .navigationTitle(Text("Looking back", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let memoriesTask = session.client.decode(
                LossyArray<Status>.self, from: Endpoint.memories.onThisDay)
            async let recapTask = session.client.decode(
                WeeklyRecap.self, from: Endpoint.memories.recap)
            memories = try await memoriesTask.elements.sorted { $0.createdAt > $1.createdAt }
            recap = try await recapTask
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func setRecap(enabled: Bool) async {
        let previous = recap
        recap = WeeklyRecap(
            enabled: enabled, thisWeek: recap?.thisWeek ?? 0, lastWeek: recap?.lastWeek ?? 0)
        do {
            _ = try await session.client.send(Endpoint.memories.setRecap(enabled: enabled))
            // The counts only come once it is on.
            if enabled {
                recap = try await session.client.decode(
                    WeeklyRecap.self, from: Endpoint.memories.recap)
            }
        } catch {
            recap = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

/// "3 years ago — what you wrote", one line per memory.
struct MemoryRow: View {
    @Environment(\.alohaPalette) private var palette

    let status: Status
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: AlohaMetrics.space3) {
                Text(yearsAgo)
                    .font(AlohaType.meta.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(width: 84, alignment: .leading)
                Text(excerpt)
                    .font(.footnote)
                    .foregroundStyle(palette.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(yearsAgo). \(excerpt)", comment: "Memory row"))
    }

    private var yearsAgo: String {
        let years = max(
            1,
            Calendar.current.dateComponents([.year], from: status.createdAt, to: Date()).year ?? 1)
        return String(localized: "^[\(years) year](inflect: true) ago", comment: "Memory age")
    }

    private var excerpt: String {
        let target = status.displayed
        if !target.spoilerText.isEmpty { return target.spoilerText }
        let plain = StatusHTMLParser().plainText(target.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.isEmpty, !target.mediaAttachments.isEmpty {
            return String(
                localized: "^[\(target.mediaAttachments.count) attachment](inflect: true)",
                comment: "Memory with media only")
        }
        return plain.count > 140 ? String(plain.prefix(140)) + "…" : plain
    }
}

/// The recap's one sentence, shared by the screen and the home card.
struct WeeklyRecapSummary: View {
    @Environment(\.alohaPalette) private var palette

    let recap: WeeklyRecap

    var body: some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                headline
                    .font(.subheadline.weight(.semibold))
                comparison
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
    }

    private var headline: Text {
        if recap.thisWeek == 0 {
            return Text("Nothing posted this week yet.", comment: "Weekly recap headline")
        }
        return Text(
            "^[\(recap.thisWeek) post](inflect: true) this week.", comment: "Weekly recap headline")
    }

    private var comparison: Text {
        if recap.lastWeek == 0 && recap.thisWeek == 0 {
            return Text("Last week was quiet too.", comment: "Weekly recap comparison")
        }
        if recap.thisWeek > recap.lastWeek {
            return Text(
                "Up from ^[\(recap.lastWeek) post](inflect: true) last week.",
                comment: "Weekly recap comparison")
        }
        if recap.thisWeek < recap.lastWeek {
            return Text(
                "Down from ^[\(recap.lastWeek) post](inflect: true) last week.",
                comment: "Weekly recap comparison")
        }
        return Text("The same as last week.", comment: "Weekly recap comparison")
    }
}
