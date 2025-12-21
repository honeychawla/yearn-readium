import AVFoundation
import Combine
import Foundation
import R2Navigator
import R2Shared
import UIKit

/// View controller for playing LCP-protected audiobooks
final class AudiobookViewController: ReaderViewController {

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?

    // UI Elements
    private lazy var playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        button.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        button.tintColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var progressSlider: UISlider = {
        let slider = UISlider()
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .darkGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(
        publication: Publication,
        locator: Locator?,
        bookId: String
    ) throws {
        // Create a simple navigator that doesn't display anything
        // The audio playback will be handled by AVPlayer
        let navigator = SimpleNavigator(publication: publication)

        super.init(
            navigator: navigator,
            publication: publication,
            bookId: bookId
        )

        setupAudioPlayer()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupUI()
    }

    private func setupUI() {
        // Add playback controls
        view.addSubview(playPauseButton)
        view.addSubview(progressSlider)
        view.addSubview(currentTimeLabel)
        view.addSubview(durationLabel)

        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 80),
            playPauseButton.heightAnchor.constraint(equalToConstant: 80),

            progressSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            progressSlider.topAnchor.constraint(equalTo: playPauseButton.bottomAnchor, constant: 40),

            currentTimeLabel.leadingAnchor.constraint(equalTo: progressSlider.leadingAnchor),
            currentTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 8),

            durationLabel.trailingAnchor.constraint(equalTo: progressSlider.trailingAnchor),
            durationLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 8),
        ])
    }

    private func setupAudioPlayer() {
        // Get the first audio resource from the reading order
        // readingOrder returns Link? so we just use .first directly
        guard let audioLink = publication.readingOrder.first else {
            print("[Audiobook] No audio resource found in reading order")
            return
        }

        print("[Audiobook] Found audio resource:", audioLink.href)
        print("[Audiobook] Media type:", audioLink.mediaType.string)

        // Get the absolute URL for the resource
        // The publication server will serve it with LCP decryption
        guard let url = audioLink.url(relativeTo: publication.baseURL) else {
            print("[Audiobook] Failed to get resource URL")
            return
        }

        print("[Audiobook] Resource URL:", url)
        createPlayerWithURL(url)
    }

    private func createPlayerWithURL(_ url: URL) {
        print("[Audiobook] Creating player with URL:", url.absoluteString)

        // Create AVPlayer with the resource URL
        // The PublicationServer will handle LCP decryption when the resource is accessed
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Update duration label when asset is loaded
        playerItem?.asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let duration = self.playerItem?.asset.duration.seconds, !duration.isNaN {
                    self.durationLabel.text = self.formatTime(duration)
                    self.progressSlider.maximumValue = Float(duration)
                    print("[Audiobook] Duration loaded:", duration)
                }
            }
        }

        // Add time observer to update progress
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgress(time)
        }

        print("[Audiobook] Player ready")
    }

    private func updateProgress(_ time: CMTime) {
        let currentTime = time.seconds
        guard !currentTime.isNaN else { return }

        currentTimeLabel.text = formatTime(currentTime)
        progressSlider.value = Float(currentTime)

        // Update locator for progress saving
        if let duration = playerItem?.duration.seconds, !duration.isNaN, duration > 0 {
            _ = currentTime / duration
            // TODO: Create and emit proper audiobook locator with progression
        }
    }

    @objc private func togglePlayPause() {
        guard let player = player else { return }

        if player.timeControlStatus == .playing {
            player.pause()
            playPauseButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        } else {
            player.play()
            playPauseButton.setImage(UIImage(systemName: "pause.circle.fill"), for: .normal)
        }
    }

    @objc private func sliderValueChanged() {
        let newTime = CMTime(seconds: Double(progressSlider.value), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: newTime)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
    }
}

// MARK: - Simple Navigator for Audiobooks

/// A simple navigator that conforms to Navigator protocol but doesn't display anything
/// The actual audio playback is handled by AVPlayer in AudiobookViewController
private class SimpleNavigator: UIViewController, Navigator {
    let publication: Publication
    var currentLocation: Locator? {
        // Return first item in reading order
        return publication.readingOrder.first.flatMap { publication.locate($0) }
    }

    init(publication: Publication) {
        self.publication = publication
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func go(to locator: Locator, animated: Bool, completion: @escaping () -> Void) -> Bool {
        completion()
        return true
    }

    func go(to link: Link, animated: Bool, completion: @escaping () -> Void) -> Bool {
        completion()
        return true
    }

    func goForward(animated: Bool, completion: @escaping () -> Void) -> Bool {
        completion()
        return true
    }

    func goBackward(animated: Bool, completion: @escaping () -> Void) -> Bool {
        completion()
        return true
    }
}
