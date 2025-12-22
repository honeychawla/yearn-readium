import AVFoundation
import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// View controller for playing LCP-protected audiobooks
final class AudiobookViewController: ReaderViewController, AudioNavigatorDelegate {

    private var audioNavigator: AudioNavigator?

    // Book metadata
    private var bookTitle: String
    private var bookAuthor: String
    private var coverImageURL: URL?

    // Colors matching the TypeScript player
    private let backgroundColor = UIColor(red: 0x19/255.0, green: 0x27/255.0, blue: 0x44/255.0, alpha: 1.0) // #192744
    private let primaryColor = UIColor(red: 0xF5/255.0, green: 0xE5/255.0, blue: 0xD5/255.0, alpha: 1.0) // #F5E5D5
    private let secondaryColor = UIColor(red: 0x8B/255.0, green: 0x9B/255.0, blue: 0x99/255.0, alpha: 1.0) // #8B9B99
    private let accentColor = UIColor(red: 0xC5/255.0, green: 0xB1/255.0, blue: 0x89/255.0, alpha: 1.0) // #c5b189
    private let buttonColor = UIColor(red: 0x09/255.0, green: 0x1E/255.0, blue: 0x3D/255.0, alpha: 1.0) // #091e3d

    // Loading UI
    private lazy var loadingContainer: UIView = {
        let view = UIView()
        view.backgroundColor = backgroundColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = accentColor
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Preparing audiobook..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = primaryColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor = accentColor
        progress.trackTintColor = secondaryColor.withAlphaComponent(0.3)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()

    // Player UI Elements
    private lazy var coverImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = UIColor(red: 0x33/255.0, green: 0x46/255.0, blue: 0x5C/255.0, alpha: 1.0)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24, weight: .regular)
        label.textColor = primaryColor
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var authorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = secondaryColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var playPauseButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 48)), for: .normal)
        button.tintColor = buttonColor
        button.backgroundColor = accentColor
        button.layer.cornerRadius = 40
        button.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var skipBackButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "gobackward.15", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        button.tintColor = primaryColor
        button.addTarget(self, action: #selector(skipBackward), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var skipForwardButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "goforward.30", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        button.tintColor = primaryColor
        button.addTarget(self, action: #selector(skipForward), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var progressSlider: UISlider = {
        let slider = UISlider()
        slider.minimumTrackTintColor = UIColor(red: 0xD4/255.0, green: 0xC4/255.0, blue: 0xA8/255.0, alpha: 1.0)
        slider.maximumTrackTintColor = UIColor(red: 0x6D/255.0, green: 0x7B/255.0, blue: 0x7C/255.0, alpha: 1.0)
        slider.thumbTintColor = primaryColor
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = secondaryColor
        label.text = "0:00"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = secondaryColor
        label.textAlignment = .right
        label.text = "0:00"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(
        publication: Publication,
        locator: Locator?,
        bookId: String
    ) throws {
        // Extract metadata from publication
        self.bookTitle = publication.metadata.title
        self.bookAuthor = publication.metadata.authors.first?.name ?? "Unknown"

        // Get cover image URL if available
        if let coverLink = publication.links.first(where: { $0.rels.contains("cover") }) {
            self.coverImageURL = coverLink.url(relativeTo: publication.baseURL)
        }

        // Create Readium's AudioNavigator (handles LCP decryption properly)
        let audioNavigator = AudioNavigator(
            publication: publication,
            initialLocation: locator
        )
        self.audioNavigator = audioNavigator

        // Create wrapper view controller for the navigator
        let navigatorWrapper = AudioNavigatorWrapper(audioNavigator: audioNavigator)

        super.init(
            navigator: navigatorWrapper,
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

        view.backgroundColor = backgroundColor
        setupUI()
        loadMetadata()
    }

    private func loadMetadata() {
        // Set title and author
        titleLabel.text = bookTitle
        authorLabel.text = bookAuthor

        // Load cover image if available
        if let coverURL = coverImageURL {
            loadCoverImage(from: coverURL)
        } else {
            // Show placeholder emoji if no cover
            let label = UILabel()
            label.text = "🎧"
            label.font = .systemFont(ofSize: 80)
            label.textAlignment = .center
            label.frame = coverImageView.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            coverImageView.addSubview(label)
        }
    }

    private func loadCoverImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                return
            }
            DispatchQueue.main.async {
                self?.coverImageView.image = image
            }
        }.resume()
    }

    private func setupUI() {
        // Add loading UI
        view.addSubview(loadingContainer)
        loadingContainer.addSubview(activityIndicator)
        loadingContainer.addSubview(loadingLabel)
        loadingContainer.addSubview(progressView)

        // Add player UI (hidden initially)
        view.addSubview(coverImageView)
        view.addSubview(titleLabel)
        view.addSubview(authorLabel)
        view.addSubview(progressSlider)
        view.addSubview(currentTimeLabel)
        view.addSubview(durationLabel)
        view.addSubview(skipBackButton)
        view.addSubview(playPauseButton)
        view.addSubview(skipForwardButton)

        coverImageView.alpha = 0
        titleLabel.alpha = 0
        authorLabel.alpha = 0
        playPauseButton.alpha = 0
        skipBackButton.alpha = 0
        skipForwardButton.alpha = 0
        progressSlider.alpha = 0
        currentTimeLabel.alpha = 0
        durationLabel.alpha = 0

        NSLayoutConstraint.activate([
            // Loading container
            loadingContainer.topAnchor.constraint(equalTo: view.topAnchor),
            loadingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor, constant: -40),

            loadingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingContainer.leadingAnchor, constant: 40),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingContainer.trailingAnchor, constant: -40),

            progressView.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: loadingContainer.leadingAnchor, constant: 40),
            progressView.trailingAnchor.constraint(equalTo: loadingContainer.trailingAnchor, constant: -40),

            // Cover art
            coverImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coverImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            coverImageView.widthAnchor.constraint(equalToConstant: 280),
            coverImageView.heightAnchor.constraint(equalToConstant: 280),

            // Title and author
            titleLabel.topAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            authorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            authorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            authorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            // Progress slider
            progressSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            progressSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            progressSlider.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 32),

            currentTimeLabel.leadingAnchor.constraint(equalTo: progressSlider.leadingAnchor),
            currentTimeLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 8),

            durationLabel.trailingAnchor.constraint(equalTo: progressSlider.trailingAnchor),
            durationLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 8),

            // Playback controls
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playPauseButton.topAnchor.constraint(equalTo: currentTimeLabel.bottomAnchor, constant: 32),
            playPauseButton.widthAnchor.constraint(equalToConstant: 80),
            playPauseButton.heightAnchor.constraint(equalToConstant: 80),

            skipBackButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -32),
            skipBackButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            skipBackButton.widthAnchor.constraint(equalToConstant: 44),
            skipBackButton.heightAnchor.constraint(equalToConstant: 44),

            skipForwardButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 32),
            skipForwardButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            skipForwardButton.widthAnchor.constraint(equalToConstant: 44),
            skipForwardButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Start loading animation
        activityIndicator.startAnimating()
    }

    private func setupAudioPlayer() {
        print("[Audiobook] Using AudioNavigator for playback...")

        guard let navigator = audioNavigator else {
            print("[Audiobook] ❌ No audio navigator")
            return
        }

        navigator.delegate = self

        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setActive(false)
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("[Audiobook] ✅ Audio session activated")
        } catch {
            print("[Audiobook] ❌ Audio session error:", error)
        }

        // Show UI after short delay, then auto-play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hideLoadingAndShowPlayer()

            // Auto-play
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let nav = self?.audioNavigator else { return }
                nav.play()
                print("[Audiobook] ▶️ Started playback via AudioNavigator")
            }
        }
    }

    // MARK: - AudioNavigatorDelegate

    func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
        print("[Audiobook] 📊 Playback:", info.state, "time:", info.time)

        // Update UI
        currentTimeLabel.text = formatTime(info.time)
        if let duration = info.duration {
            durationLabel.text = formatTime(duration)
            progressSlider.maximumValue = Float(duration)
        }
        progressSlider.value = Float(info.time)

        // Update button
        let isPlaying = info.state == .playing
        let icon = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        playPauseButton.setImage(
            UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 48)),
            for: .normal
        )
    }

    private func hideLoadingAndShowPlayer() {
        UIView.animate(withDuration: 0.3) {
            self.loadingContainer.alpha = 0
            self.coverImageView.alpha = 1
            self.titleLabel.alpha = 1
            self.authorLabel.alpha = 1
            self.playPauseButton.alpha = 1
            self.skipBackButton.alpha = 1
            self.skipForwardButton.alpha = 1
            self.progressSlider.alpha = 1
            self.currentTimeLabel.alpha = 1
            self.durationLabel.alpha = 1
        } completion: { _ in
            self.loadingContainer.removeFromSuperview()
            self.activityIndicator.stopAnimating()
        }
    }

    @objc private func togglePlayPause() {
        guard let navigator = audioNavigator else { return }

        if navigator.playbackInfo.state == .playing {
            navigator.pause()
        } else {
            navigator.play()
        }
    }

    @objc private func skipBackward() {
        guard let navigator = audioNavigator else { return }
        let currentTime = navigator.playbackInfo.time
        navigator.seek(to: max(currentTime - 15, 0))
    }

    @objc private func skipForward() {
        guard let navigator = audioNavigator else { return }
        let currentTime = navigator.playbackInfo.time
        let duration = navigator.playbackInfo.duration ?? 0
        navigator.seek(to: min(currentTime + 30, duration))
    }

    @objc private func sliderValueChanged() {
        guard let navigator = audioNavigator else { return }
        navigator.seek(to: Double(progressSlider.value))
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
        audioNavigator?.pause()
    }
}

// MARK: - Audio Navigator Wrapper

/// Wrapper to make AudioNavigator conform to UIViewController & Navigator
private class AudioNavigatorWrapper: UIViewController, Navigator {
    let audioNavigator: AudioNavigator

    var publication: Publication {
        return audioNavigator.publication
    }

    var currentLocation: Locator? {
        return audioNavigator.currentLocation
    }

    init(audioNavigator: AudioNavigator) {
        self.audioNavigator = audioNavigator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func go(to locator: Locator, animated: Bool, completion: @escaping () -> Void) -> Bool {
        return audioNavigator.go(to: locator, animated: animated, completion: completion)
    }

    func go(to link: Link, animated: Bool, completion: @escaping () -> Void) -> Bool {
        return audioNavigator.go(to: link, animated: animated, completion: completion)
    }

    func goForward(animated: Bool, completion: @escaping () -> Void) -> Bool {
        return audioNavigator.goForward(animated: animated, completion: completion)
    }

    func goBackward(animated: Bool, completion: @escaping () -> Void) -> Bool {
        return audioNavigator.goBackward(animated: animated, completion: completion)
    }
}
