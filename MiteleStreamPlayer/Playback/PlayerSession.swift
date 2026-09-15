import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

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
    @ObservationIgnored private let progressStore: WatchProgressStore
    @ObservationIgnored private var transport: PlayerTransport
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var cues: [SubtitleCue] = []
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var hasAttemptedResume = false
    @ObservationIgnored private var lastProgressSaveDate: Date?

    init(
        stream: ResolvedStream,
        progressStore: WatchProgressStore,
        factory: any PlayerItemBuilding = AVPlayerItemFactory()
    ) {
        self.stream = stream
        self.progressStore = progressStore
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
        configureNowPlaying()
    }

    func stop() {
        saveProgressNow()
        subtitleTask?.cancel()
        subtitleTask = nil
        artworkTask?.cancel()
        artworkTask = nil
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
        clearNowPlaying()
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
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                self?.updateSubtitleText(at: seconds)
                self?.updateNowPlayingPlaybackInfo()
                self?.saveProgressIfDue(at: seconds)
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

    /// Drives Control Center / Lock Screen "Now Playing" — AVKit's own automatic mode
    /// (`updatesNowPlayingInfoCenter`) relies on metadata embedded in the asset itself, which
    /// these raw HLS streams don't carry, so title/status/artwork are set manually instead.
    private func configureNowPlaying() {
        setUpRemoteCommands()
        updateNowPlayingInfo()
    }

    /// Fetching + decoding the artwork previously ran inline on the (MainActor-inherited) `Task`
    /// created from `start()`, immediately as the fullscreen presentation was still transitioning
    /// in — and reliably crashed VOD playback. This version keeps the network fetch and `UIImage`
    /// decode fully off the main actor via `Task.detached`, only hops back to update state once
    /// the image is ready, and only starts once the item has actually reported `.readyToPlay`
    /// (see `handle(_:)`) so it never runs during the initial transition.
    private func loadArtworkIfNeeded() {
        guard artworkTask == nil, let url = stream.artworkURL else { return }
        artworkTask = Task.detached(priority: .utility) { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
                self?.nowPlayingArtwork = artwork
                self?.updateNowPlayingInfo()
            }
        }
    }

    private func setUpRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        // Left disabled: AVPlayerViewController's own native transport bar already manages
        // scrubbing for seekable (VOD) content, and registering a competing handler for the
        // same command crashed VOD playback.
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player.play()
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if player.timeControlStatus == .playing {
                player.pause()
            } else {
                player.play()
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: stream.title,
            MPNowPlayingInfoPropertyIsLiveStream: stream.isLive,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate
        ]
        if !stream.isLive {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
            if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        if !stream.isLive {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
            if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
            loadArtworkIfNeeded()
            resumeIfNeeded()
        case .failed:
            retryWithFallbackOrFail()
        case .unknown:
            isLoading = true
        @unknown default:
            retryWithFallbackOrFail()
        }
    }

    /// Seeks to a previously saved position the first time the item becomes ready. Guarded to
    /// run once per session — if a header-fallback retry re-fires `.readyToPlay` on a new item,
    /// we're already past the resume point and re-seeking to the original saved position would
    /// rewind unexpectedly.
    private func resumeIfNeeded() {
        guard !hasAttemptedResume else { return }
        hasAttemptedResume = true
        guard !stream.isLive, let contentID = stream.contentID,
              let saved = progressStore.progress(for: contentID) else { return }
        let time = CMTime(seconds: saved.positionSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Persists progress at most every few seconds during playback, so a saved position exists
    /// even if the app is killed rather than closed normally through `stop()`.
    private func saveProgressIfDue(at seconds: Double) {
        guard !stream.isLive, stream.contentID != nil, seconds.isFinite else { return }
        let now = Date.now
        if let last = lastProgressSaveDate, now.timeIntervalSince(last) < 5 { return }
        lastProgressSaveDate = now
        persistProgress(position: seconds)
    }

    private func saveProgressNow() {
        guard !stream.isLive, stream.contentID != nil else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        persistProgress(position: seconds)
    }

    private func persistProgress(position: Double) {
        guard let contentID = stream.contentID,
              let duration = player.currentItem?.duration.seconds, duration.isFinite else { return }
        Task { await progressStore.update(contentID: contentID, position: position, duration: duration) }
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
