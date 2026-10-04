import AVFoundation
import AlohaMedia
import AlohaModels
import Network
import Observation

/// One paused, muted player for the next short. Nothing is persisted to disk.
@MainActor
@Observable
final class NextVideoPreloader {
    struct Key: Hashable, Sendable {
        let accountID: UUID
        let statusID: String
        let attachmentID: String
    }
    private(set) var allowsPrefetch = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var cached: [Key: (player: AVPlayer, item: AVPlayerItem)] = [:]
    @ObservationIgnored private var requestID = UUID()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let allowed = path.status == .satisfied && !path.isExpensive && !path.isConstrained
            Task { @MainActor [weak self] in self?.allowsPrefetch = allowed }
        }
        monitor.start(queue: DispatchQueue(label: "aloha.video-prefetch.network"))
    }

    deinit { monitor.cancel() }

    nonisolated static func key(accountID: UUID, statusID: String, attachmentID: String) -> Key {
        Key(accountID: accountID, statusID: statusID, attachmentID: attachmentID)
    }

    nonisolated static func permits(networkAllowed: Bool, lowPower: Bool, autoplay: Bool, covered: Bool) -> Bool {
        networkAllowed && !lowPower && autoplay && !covered
    }

    func cancel() {
        requestID = UUID()
        for entry in cached.values {
            entry.player.cancelPendingPrerolls()
            entry.player.pause()
            entry.player.replaceCurrentItem(with: nil)
        }
        cached.removeAll()
    }

    func take(key: Key) -> (AVPlayer, AVPlayerItem)? {
        guard let cached = cached.removeValue(forKey: key), cached.item.status != .failed else { return nil }
        cached.player.cancelPendingPrerolls()
        return (cached.player, cached.item)
    }

    func retainCurrent(statusID: String, accountID: UUID) {
        requestID = UUID()
        for key in Array(cached.keys) where key.accountID != accountID || key.statusID != statusID {
            let entry = cached.removeValue(forKey: key)
            entry?.player.cancelPendingPrerolls()
            entry?.player.replaceCurrentItem(with: nil)
        }
    }

    func prepare(status: Status, keeping currentStatusID: String, session: AccountSession) async {
        requestID = UUID()
        let token = requestID
        let target = status.displayed
        for key in Array(cached.keys) where key.accountID != session.id
            || (key.statusID != currentStatusID && key.statusID != target.id) {
            let entry = cached.removeValue(forKey: key)
            entry?.player.cancelPendingPrerolls()
            entry?.player.replaceCurrentItem(with: nil)
        }
        guard Self.permits(networkAllowed: allowsPrefetch,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            autoplay: session.settings.autoplayVideo,
            covered: target.sensitive && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal),
            let attachment = target.mediaAttachments.first(where: { $0.isVideo })
        else {
            retainCurrent(statusID: currentStatusID, accountID: session.id)
            return
        }
        let targetKey = Self.key(accountID: session.id, statusID: target.id, attachmentID: attachment.id)
        if cached[targetKey] != nil { return }
        let sources = VideoSourceResolver.sources(for: attachment, statusID: target.id,
            apiBase: session.capabilities.apiBase, isRemote: VideoSourceResolver.isRemote(attachment))
        for source in sources {
            guard !Task.isCancelled, requestID == token else { return }
            let headers = await session.client.mediaRequestHeaders(for: source.url)
            switch await PlaybackReadiness.open(url: source.url, headers: headers) {
            case .playable(let player, let item, let ready):
                guard !Task.isCancelled, requestID == token else {
                    player.replaceCurrentItem(with: nil)
                    return
                }
                player.isMuted = true
                item.preferredForwardBufferDuration = 3
                item.preferredPeakBitRate = 1_500_000
                cached[Self.key(accountID: session.id, statusID: target.id,
                    attachmentID: attachment.id)] = (player, item)
                if ready, player.status == .readyToPlay {
                    player.preroll(atRate: 1, completionHandler: nil)
                }
                return
            case .rejected:
                continue
            }
        }
    }
}
