import AVFoundation
import Foundation
import Observation

struct PlayerTransport {
    let item: AVPlayerItem
    let resourceLoader: HeaderResourceLoader?
}

@MainActor
protocol PlayerItemBuilding {
    func standardItem(for stream: ResolvedStream) -> PlayerTransport
    func fallbackItem(for stream: ResolvedStream) -> PlayerTransport?
}

@MainActor
struct AVPlayerItemFactory: PlayerItemBuilding {
    func standardItem(for stream: ResolvedStream) -> PlayerTransport {
        let options = ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
        let asset = AVURLAsset(url: stream.url, options: options)
        return PlayerTransport(item: AVPlayerItem(asset: asset), resourceLoader: nil)
    }

    func fallbackItem(for stream: ResolvedStream) -> PlayerTransport? {
        guard let url = HeaderResourceLoader.customURL(from: stream.url) else { return nil }
        let loader = HeaderResourceLoader(headers: stream.headers)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: loader.resourceQueue)
        return PlayerTransport(item: AVPlayerItem(asset: asset), resourceLoader: loader)
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
    var subtitlesEnabled = true
    var subtitleText: String?

    var hasSubtitles: Bool { !stream.subtitles.isEmpty }

    @ObservationIgnored private let stream: ResolvedStream
    @ObservationIgnored private let factory: any PlayerItemBuilding
    @ObservationIgnored private var transport: PlayerTransport
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    @ObservationIgnored private var cues: [SubtitleCue] = []

    init(
        stream: ResolvedStream,
        factory: any PlayerItemBuilding = AVPlayerItemFactory()
    ) {
        self.stream = stream
        self.factory = factory
        title = stream.title
        let initial = factory.standardItem(for: stream)
        transport = initial
        player = AVPlayer(playerItem: initial.item)
        observe(initial.item)
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
        player.play()
        loadSubtitlesIfNeeded()
        addTimeObserverIfNeeded()
    }

    func stop() {
        subtitleTask?.cancel()
        subtitleTask = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func toggleSubtitles() {
        subtitlesEnabled.toggle()
        if !subtitlesEnabled {
            subtitleText = nil
        }
    }

    /// Fetches and parses the WebVTT sidecar manually and drives a text overlay from it, instead
    /// of handing it to AVFoundation as a composed media-selection track (see WebVTTParser).
    private func loadSubtitlesIfNeeded() {
        guard hasSubtitles, subtitleTask == nil, let url = stream.subtitles.first?.url else { return }
        subtitleTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                self?.cues = WebVTTParser.parse(String(decoding: data, as: UTF8.self))
            } catch {
                self?.cues = []
            }
        }
    }

    private func addTimeObserverIfNeeded() {
        guard timeObserver == nil, hasSubtitles else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                self?.updateSubtitleText(at: seconds)
            }
        }
    }

    private func updateSubtitleText(at seconds: Double) {
        guard subtitlesEnabled, seconds.isFinite else {
            if subtitleText != nil { subtitleText = nil }
            return
        }
        let active = cues.first { $0.start <= seconds && seconds <= $0.end }
        if subtitleText != active?.text {
            subtitleText = active?.text
        }
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
        guard stream.allowsHeaderFallback, !isUsingFallback,
              let fallback = factory.fallbackItem(for: stream) else {
            failure = .playback
            isLoading = false
            return
        }
        isUsingFallback = true
        isLoading = true
        transport = fallback
        observe(fallback.item)
        player.replaceCurrentItem(with: fallback.item)
        player.play()
    }
}
