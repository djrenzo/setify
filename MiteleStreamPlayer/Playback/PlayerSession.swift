import AVFoundation
import Foundation
import Observation

struct PlayerTransport {
    let item: AVPlayerItem
    let resourceLoader: HeaderResourceLoader?
}

@MainActor
protocol PlayerItemBuilding {
    func standardItem(for stream: ResolvedStream) async -> PlayerTransport
    func fallbackItem(for stream: ResolvedStream) async -> PlayerTransport?
}

@MainActor
struct AVPlayerItemFactory: PlayerItemBuilding {
    func standardItem(for stream: ResolvedStream) async -> PlayerTransport {
        let options = ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
        let asset = AVURLAsset(url: stream.url, options: options)
        let item = await Self.playerItem(for: asset, subtitles: stream.subtitles)
        return PlayerTransport(item: item, resourceLoader: nil)
    }

    func fallbackItem(for stream: ResolvedStream) async -> PlayerTransport? {
        guard let url = HeaderResourceLoader.customURL(from: stream.url) else { return nil }
        let loader = HeaderResourceLoader(headers: stream.headers)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: loader.resourceQueue)
        let item = await Self.playerItem(for: asset, subtitles: stream.subtitles)
        return PlayerTransport(item: item, resourceLoader: loader)
    }

    /// Builds a plain item when there are no subtitles to attach. Otherwise composes the video
    /// asset with the WebVTT sidecar tracks so AVKit's native controls expose a subtitle picker.
    /// If composing fails for any reason (e.g. the stream can't be composed), falls back to plain
    /// playback without subtitles rather than breaking video.
    private static func playerItem(for asset: AVURLAsset, subtitles: [SubtitleTrack]) async -> AVPlayerItem {
        guard !subtitles.isEmpty,
              let composition = try? await composedAsset(videoAsset: asset, subtitles: subtitles) else {
            return AVPlayerItem(asset: asset)
        }
        return AVPlayerItem(asset: composition)
    }

    private static func composedAsset(
        videoAsset: AVURLAsset,
        subtitles: [SubtitleTrack]
    ) async throws -> AVComposition {
        let composition = AVMutableComposition()
        let duration = try await videoAsset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        // Video/audio insertion failures must propagate (not be swallowed) — an empty
        // composition would silently produce a broken, non-playing item.
        for mediaType in [AVMediaType.video, .audio] {
            let tracks = try await videoAsset.loadTracks(withMediaType: mediaType)
            for track in tracks {
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                try compositionTrack.insertTimeRange(timeRange, of: track, at: .zero)
            }
        }

        // A single bad subtitle track shouldn't take down the others or the video itself.
        for subtitle in subtitles {
            try? await insertSubtitleTrack(subtitle, into: composition)
        }
        return composition
    }

    private static func insertSubtitleTrack(
        _ subtitle: SubtitleTrack,
        into composition: AVMutableComposition
    ) async throws {
        let subtitleAsset = AVURLAsset(url: subtitle.url)
        guard let textTrack = try await subtitleAsset.loadTracks(withMediaType: .text).first,
              let compositionTrack = composition.addMutableTrack(
                withMediaType: .text,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { return }
        let subtitleDuration = try await subtitleAsset.load(.duration)
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: subtitleDuration),
            of: textTrack,
            at: .zero
        )
        compositionTrack.extendedLanguageTag = subtitle.languageTag
    }
}

@MainActor
@Observable
final class PlayerSession {
    let title: String
    let player: AVPlayer

    var isLoading = true
    var isUsingFallback = false
    var failure: PlaybackFailure?

    @ObservationIgnored private let stream: ResolvedStream
    @ObservationIgnored private let factory: any PlayerItemBuilding
    @ObservationIgnored private var transport: PlayerTransport?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemTask: Task<Void, Never>?

    init(
        stream: ResolvedStream,
        factory: any PlayerItemBuilding = AVPlayerItemFactory()
    ) {
        self.stream = stream
        self.factory = factory
        title = stream.title
        player = AVPlayer()
    }

    func start() {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .moviePlayback)
            try audio.setActive(true)
        } catch {
            failure = .playback
            isLoading = false
            return
        }
        guard itemTask == nil else { return }
        isLoading = true
        itemTask = Task { [weak self] in
            guard let self else { return }
            let initial = await factory.standardItem(for: stream)
            guard !Task.isCancelled else { return }
            attach(initial)
            player.play()
        }
    }

    func stop() {
        itemTask?.cancel()
        itemTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func attach(_ transport: PlayerTransport) {
        self.transport = transport
        observe(transport.item)
        player.replaceCurrentItem(with: transport.item)
    }

    private func observe(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                self?.handle(status)
            }
        }
    }

    private func handle(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            isLoading = false
            failure = nil
        case .failed:
            retryWithFallbackOrFail()
        case .unknown:
            isLoading = true
        @unknown default:
            retryWithFallbackOrFail()
        }
    }

    private func retryWithFallbackOrFail() {
        guard stream.allowsHeaderFallback, !isUsingFallback else {
            failure = .playback
            isLoading = false
            return
        }
        isUsingFallback = true
        isLoading = true
        itemTask = Task { [weak self] in
            guard let self else { return }
            guard let fallback = await factory.fallbackItem(for: stream) else {
                failure = .playback
                isLoading = false
                return
            }
            guard !Task.isCancelled else { return }
            attach(fallback)
            player.play()
        }
    }
}
