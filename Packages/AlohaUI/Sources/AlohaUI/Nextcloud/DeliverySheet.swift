// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Where a post got to, server by server. Author only; the server refuses
/// anybody else, and the menu item only appears on your own posts.
public struct DeliverySheet: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let status: Status
    private let session: AccountSession

    @State private var report: DeliveryReport?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(status: Status, session: AccountSession) {
        self.status = status
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            List {
                if let report {
                    Section {
                        summary(report)
                    }
                    Section {
                        ForEach(report.instances) { instance in
                            row(instance)
                        }
                        if report.instances.isEmpty {
                            Text("No servers to deliver to yet.", comment: "Delivery empty state")
                                .font(.footnote)
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                    } header: {
                        Text("Servers", comment: "Delivery section")
                    } footer: {
                        Text(
                            "Rows are kept for \(Duration.seconds(report.retention), format: .units(allowed: [.days, .hours], width: .wide)).",
                            comment: "Delivery retention footer")
                    }
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                }
            }
            .navigationTitle(Text("Delivery", comment: "Screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Sheet action")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: - Pieces

    private func summary(_ report: DeliveryReport) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text(
                "Delivered to ^[\(report.delivered) server](inflect: true) of \(report.total).",
                comment: "Delivery summary line"
            )
            .font(.subheadline.weight(.semibold))

            HStack(spacing: AlohaMetrics.space3) {
                if report.sending > 0 {
                    count(report.sending, state: .sending)
                }
                if report.waiting > 0 {
                    count(report.waiting, state: .waiting)
                }
                if report.failing > 0 {
                    count(report.failing, state: .failing)
                }
                if report.abandoned > 0 {
                    count(report.abandoned, state: .abandoned)
                }
            }
            .font(AlohaType.meta)
            .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.vertical, AlohaMetrics.space1)
    }

    private func count(_ value: Int, state: DeliveryInstance.State) -> some View {
        HStack(spacing: 4) {
            dot(state)
            Text(value, format: .number)
            label(state)
        }
    }

    private func row(_ instance: DeliveryInstance) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            dot(instance.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.host)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: AlohaMetrics.space1) {
                    label(instance.state)
                    if instance.tries > 1 {
                        Text(verbatim: "·")
                        Text("^[\(instance.tries) try](inflect: true)", comment: "Delivery tries")
                    }
                    if let last = instance.last {
                        Text(verbatim: "·")
                        Text(last, format: .relative(presentation: .named))
                    }
                }
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Colour and a word, never colour alone (docs/12 §3).
    private func label(_ state: DeliveryInstance.State) -> Text {
        switch state {
        case .delivered: Text("Delivered", comment: "Delivery state")
        case .sending: Text("Sending", comment: "Delivery state")
        case .waiting: Text("Waiting", comment: "Delivery state")
        case .failing: Text("Failing", comment: "Delivery state")
        case .abandoned: Text("Given up", comment: "Delivery state")
        }
    }

    private func dot(_ state: DeliveryInstance.State) -> some View {
        Circle()
            .fill(colour(state))
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    private func colour(_ state: DeliveryInstance.State) -> Color {
        switch state {
        case .delivered: .green
        case .sending, .waiting: .orange
        case .failing: .orange.opacity(0.7)
        case .abandoned: palette.destructive
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            report = try await session.client.decode(
                DeliveryReport.self, from: Endpoint.statusExtras.delivery(status.id))
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Couldn't load delivery.", comment: "Delivery error")
        }
    }
}
