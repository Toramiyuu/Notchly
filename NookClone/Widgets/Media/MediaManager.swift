import AppKit
import ScriptingBridge
import Combine

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var source: PlayerSource

    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
    }
}

enum PlayerSource: String {
    case music = "Music"
    case spotify = "Spotify"
}

// Music OSType player states (four-character codes as integers)
// kPSP = 'kPSP' = 0x6B505350
private let kMusicStatePlaying: Int = 0x6B505350
// kPSp = 'kPSp' = 0x6B505370  (note lower-case 'p')
private let kMusicStatePaused: Int  = 0x6B505370

/// Manages now-playing state from Apple Music or Spotify via ScriptingBridge KVC.
class MediaManager: ObservableObject {

    static let shared = MediaManager()

    @Published var currentTrack: TrackInfo? = nil
    @Published var isPlaying = false
    @Published var progress: Double = 0

    private var pollTimer: Timer?
    private var lastArtworkKey = ""
    private var cachedArtwork: NSImage?

    private init() {
        startPolling()
        setupNotifications()
    }

    deinit { pollTimer?.invalidate() }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        pollTimer?.tolerance = 0.2
        refresh()
    }

    private func setupNotifications() {
        let names = [
            "com.apple.Music.playerInfo",
            "com.spotify.client.PlaybackStateChanged",
        ]
        for name in names {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(playerStateChanged),
                name: NSNotification.Name(name),
                object: nil
            )
        }
    }

    @objc private func playerStateChanged() {
        DispatchQueue.main.async { self.refresh() }
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Skip expensive ScriptingBridge calls when neither player is running
            let apps = NSWorkspace.shared.runningApplications
            let musicRunning = apps.contains { $0.bundleIdentifier == "com.apple.Music" }
            let spotifyRunning = apps.contains { $0.bundleIdentifier == "com.spotify.client" }
            guard musicRunning || spotifyRunning else {
                DispatchQueue.main.async {
                    if self.currentTrack != nil {
                        self.currentTrack = nil
                        self.isPlaying = false
                        self.progress = 0
                    }
                }
                return
            }
            let info = (musicRunning ? self.fetchMusicInfo() : nil)
                    ?? (spotifyRunning ? self.fetchSpotifyInfo() : nil)
            DispatchQueue.main.async {
                self.currentTrack = info
                self.isPlaying = info?.isPlaying ?? false
                self.progress = info.map { $0.duration > 0 ? $0.position / $0.duration : 0 } ?? 0
            }
        }
    }

    // MARK: - Apple Music

    private func fetchMusicInfo() -> TrackInfo? {
        guard let app = SBApplication(bundleIdentifier: "com.apple.Music"),
              app.isRunning else { return nil }

        guard let stateValue = app.value(forKey: "playerState") as? Int else { return nil }
        guard stateValue == kMusicStatePlaying || stateValue == kMusicStatePaused else { return nil }

        guard let track = app.value(forKey: "currentTrack") as? SBObject else { return nil }

        let title = (track.value(forKey: "name") as? String) ?? ""
        let artist = (track.value(forKey: "artist") as? String) ?? ""
        let album = (track.value(forKey: "album") as? String) ?? ""
        let duration = (track.value(forKey: "duration") as? Double) ?? 0
        let position = (app.value(forKey: "playerPosition") as? Double) ?? 0

        let artKey = "\(title)-\(artist)"
        let artwork: NSImage?
        if artKey == lastArtworkKey {
            artwork = cachedArtwork
        } else {
            artwork = loadMusicArtwork(from: track)
            lastArtworkKey = artKey
            cachedArtwork = artwork
        }

        return TrackInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration,
            position: position,
            isPlaying: stateValue == kMusicStatePlaying,
            source: .music
        )
    }

    private func loadMusicArtwork(from track: SBObject) -> NSImage? {
        guard let artworks = track.value(forKey: "artworks") as? NSArray,
              let first = artworks.firstObject as? SBObject else { return nil }
        if let data = first.value(forKey: "rawData") as? Data {
            return NSImage(data: data)
        }
        return nil
    }

    // MARK: - Spotify

    private func fetchSpotifyInfo() -> TrackInfo? {
        guard let app = SBApplication(bundleIdentifier: "com.spotify.client"),
              app.isRunning else { return nil }

        guard let stateValue = app.value(forKey: "playerState") as? Int else { return nil }
        guard stateValue == kMusicStatePlaying || stateValue == kMusicStatePaused else { return nil }

        guard let track = app.value(forKey: "currentTrack") as? SBObject else { return nil }

        let title = (track.value(forKey: "name") as? String) ?? ""
        let artist = (track.value(forKey: "artist") as? String) ?? ""
        let album = (track.value(forKey: "album") as? String) ?? ""
        let durationMs = (track.value(forKey: "duration") as? Int) ?? 0
        let duration = Double(durationMs) / 1000.0
        let position = (app.value(forKey: "playerPosition") as? Double) ?? 0

        // Fetch artwork from Spotify via the artworkUrl SB key (Spotify SB dictionary, current as of Spotify 1.x)
        let artKey = "\(title)-\(artist)"
        let artwork: NSImage?
        if artKey == lastArtworkKey {
            artwork = cachedArtwork
        } else {
            artwork = nil  // Will be fetched asynchronously below
            fetchSpotifyArtwork(track: track, artKey: artKey)
        }

        return TrackInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            duration: duration,
            position: position,
            isPlaying: stateValue == kMusicStatePlaying,
            source: .spotify
        )
    }

    /// Async artwork download — updates currentTrack.artwork on main thread when complete.
    private func fetchSpotifyArtwork(track: SBObject, artKey: String) {
        guard let urlString = track.value(forKey: "artworkUrl") as? String,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            lastArtworkKey = artKey
            cachedArtwork = nil
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.lastArtworkKey = artKey
                self.cachedArtwork = image
                // Patch artwork into currentTrack without a full refresh
                if var track = self.currentTrack, track.source == .spotify {
                    track.artwork = image
                    self.currentTrack = track
                }
            }
        }.resume()
    }

    // MARK: - Playback Control (via NSAppleScript — reliable for all macOS versions)

    func togglePlayPause() {
        appleScript(for: currentTrack?.source, command: "playpause")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
    }

    func nextTrack() {
        appleScript(for: currentTrack?.source, command: "next track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func previousTrack() {
        appleScript(for: currentTrack?.source, command: "previous track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    private func appleScript(for source: PlayerSource?, command: String) {
        let appName: String
        switch source {
        case .music:    appName = "Music"
        case .spotify:  appName = "Spotify"
        case nil:       return
        }
        let src = "tell application \"\(appName)\" to \(command)"
        DispatchQueue.main.async {
            NSAppleScript(source: src)?.executeAndReturnError(nil)
        }
    }
}
