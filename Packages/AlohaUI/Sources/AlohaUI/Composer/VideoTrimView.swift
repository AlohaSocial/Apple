// SPDX-License-Identifier: MIT

import AVKit
import AlohaDesign
import AlohaMedia
import AlohaModels
import SwiftUI

/// Trim and quality before upload, with the resulting size stated up front —
/// a file that cannot be brought under the server's ceiling is refused with the
/// ceiling named, rather than uploaded and rejected (docs/07 §4).
public struct VideoTrimView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let url: URL
    private let limits: ServerLimits
    private let onReady: (MediaPreparer.Prepared) -> Void

    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var range: ClosedRange<Double> = 0...1
    @State private var quality: MediaPreparer.Quality = .high
    @State private var isExporting = false
    @State private var errorMessage: String?

    private let preparer = MediaPreparer()

    public init(
        url: URL, limits: ServerLimits,
        onReady: @escaping (MediaPreparer.Prepared) -> Void
    ) {
        self.url = url
        self.limits = limits
        self.onReady = onReady
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: AlohaMetrics.space4) {
                if let player {
                    PlayerSurface(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium)
                        .fill(palette.surfaceRaised)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { ProgressView() }
                }

                if duration > 0 { trimControls }

                Picker(selection: $quality) {
                    Text("Original", comment: "Video quality").tag(MediaPreparer.Quality.original)
                    Text("1080p", comment: "Video quality").tag(MediaPreparer.Quality.high)
                    Text("720p", comment: "Video quality").tag(MediaPreparer.Quality.medium)
                } label: {
                    Text("Quality", comment: "Video quality picker")
                }
                .pickerStyle(.segmented)

                Text(
                    "Videos on your server have to be under \(limits.videoSizeLimit.formatted(.byteCount(style: .file))).",
                    comment: "Video ceiling notice"
                )
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
                }

                Spacer()
            }
            .padding(AlohaMetrics.space4)
            .background(palette.background)
            .navigationTitle(Text("Trim video", comment: "Video trim title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await export() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Text("Use", comment: "Video trim action")
                        }
                    }
                    .disabled(isExporting || duration == 0)
                }
            }
            .task { await load() }
            .onDisappear { player?.pause() }
        }
    }

    private var trimControls: some View {
        VStack(spacing: AlohaMetrics.space2) {
            HStack {
                Text(Duration.seconds(range.lowerBound), format: .time(pattern: .minuteSecond))
                Spacer()
                Text(
                    "^[\(Int(range.upperBound - range.lowerBound)) second](inflect: true)",
                    comment: "Trimmed length"
                )
                .foregroundStyle(palette.secondaryLabel)
                Spacer()
                Text(Duration.seconds(range.upperBound), format: .time(pattern: .minuteSecond))
            }
            .font(.caption.monospacedDigit())

            // Two sliders rather than a custom two-handle control: this is
            // reachable by keyboard, VoiceOver and Switch Control for free.
            VStack(spacing: AlohaMetrics.space1) {
                Slider(
                    value: Binding(
                        get: { range.lowerBound },
                        set: { range = min($0, range.upperBound - 1)...range.upperBound }),
                    in: 0...max(1, duration)
                ) {
                    Text("Start", comment: "Trim slider label")
                }
                Slider(
                    value: Binding(
                        get: { range.upperBound },
                        set: { range = range.lowerBound...max($0, range.lowerBound + 1) }),
                    in: 0...max(1, duration)
                ) {
                    Text("End", comment: "Trim slider label")
                }
            }
        }
    }

    private func load() async {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        guard seconds.isFinite, seconds > 0 else { return }

        duration = seconds
        range = 0...seconds
        player = AVPlayer(url: url)
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let prepared = try await preparer.prepareVideo(
                at: url, trim: range, quality: quality)

            guard prepared.data.count <= limits.videoSizeLimit else {
                errorMessage = UploadPreflight.explanation(
                    for: .tooLarge(
                        size: prepared.data.count, limit: limits.videoSizeLimit, isVideo: true))
                return
            }

            onReady(prepared)
            dismiss()
        } catch {
            errorMessage = String(
                localized: "That video couldn't be prepared.", comment: "Video export failure")
        }
    }
}
