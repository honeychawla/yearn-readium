import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import ReadiumLCP
import UIKit

class AudiobookPlayerView: UIView, Loggable {
    var readerService: ReaderService?
    var audiobookViewController: AudiobookViewController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        print("[AudiobookPlayerView] 🔧 Initializing...")
        do {
            readerService = ReaderService()
            print("[AudiobookPlayerView] ✅ ReaderService initialized")
        } catch {
            print("[AudiobookPlayerView] ❌ ERROR initializing ReaderService:", error)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        do {
            readerService = ReaderService()
        } catch {
            print("[AudiobookPlayerView] ❌ ERROR initializing ReaderService:", error)
        }
    }
    var viewController: UIViewController? {
        let viewController = sequence(first: self, next: { $0.next }).first(where: { $0 is UIViewController })
        return viewController as? UIViewController
    }
    private var subscriptions = Set<AnyCancellable>()

    @objc var file: NSDictionary? = nil {
        didSet {
            print("[AudiobookPlayerView] 📥 File prop received")
            let initialLocation = file?["initialLocation"] as? NSDictionary
            let lcpPassphrase = file?["lcpPassphrase"] as? String
            let licensePath = file?["licensePath"] as? String

            if let url = file?["url"] as? String {
                print("[AudiobookPlayerView] 🎧 Loading audiobook from URL: \(url)")
                print("[AudiobookPlayerView] 🔐 Has passphrase: \(lcpPassphrase != nil)")
                print("[AudiobookPlayerView] 📜 License path: \(licensePath ?? "none")")
                if let passphrase = lcpPassphrase {
                    print("[AudiobookPlayerView] 🔐 Passphrase length: \(passphrase.count)")
                }

                // If we have a license path, open via license (proper LCP flow)
                if let licensePath = licensePath, !licensePath.isEmpty {
                    self.loadAudiobookViaLicense(licensePath: licensePath, location: initialLocation, lcpPassphrase: lcpPassphrase)
                } else {
                    self.loadAudiobook(url: url, location: initialLocation, lcpPassphrase: lcpPassphrase)
                }
            } else {
                print("[AudiobookPlayerView] ❌ ERROR: No URL provided in file prop")
            }
        }
    }

    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onPlaybackStateChange: RCTDirectEventBlock?

    func loadAudiobookViaLicense(
        licensePath: String,
        location: NSDictionary?,
        lcpPassphrase: String?
    ) {
        print("[AudiobookPlayerView] 🚀 loadAudiobookViaLicense called")
        print("[AudiobookPlayerView] 📜 License path: \(licensePath)")

        guard let readerService = self.readerService else {
            print("[AudiobookPlayerView] ❌ ERROR: ReaderService not initialized")
            return
        }

        guard let lcpService = readerService.app?.lcpService else {
            print("[AudiobookPlayerView] ❌ ERROR: LCP Service not available")
            return
        }

        Task {
            do {
                // Read license JSON from file
                let licenseURL = URL(fileURLWithPath: licensePath.replacingOccurrences(of: "file://", with: ""))
                let licenseData = try Data(contentsOf: licenseURL)
                let licenseJSON = try JSONSerialization.jsonObject(with: licenseData) as! [String: Any]

                print("[AudiobookPlayerView] 📜 License JSON loaded")

                // Acquire publication from license
                // Note: acquirePublication() doesn't take authentication parameter
                // It will use the authentication already configured in LCPService
                let result = await lcpService.acquirePublication(
                    from: .data(licenseData),
                    onProgress: { progress in
                        print("[AudiobookPlayerView] 📥 Acquisition progress:", progress)
                    }
                )

                switch result {
                case .success(let acquired):
                    print("[AudiobookPlayerView] ✅ Publication acquired via license")
                    print("[AudiobookPlayerView] 📁 Local URL:", acquired.localURL)

                    // Now open the downloaded publication
                    readerService.buildViewController(
                        url: acquired.localURL.string,
                        bookId: acquired.suggestedFilename,
                        location: location,
                        lcpPassphrase: lcpPassphrase,
                        sender: await UIApplication.shared.delegate?.window??.rootViewController,
                        completion: { vc in
                            Task { @MainActor in
                                if let audiobookVC = vc as? AudiobookViewController {
                                    print("[AudiobookPlayerView] ✅ Got AudiobookViewController")
                                    self.addViewControllerAsSubview(audiobookVC)
                                }
                            }
                        }
                    )

                case .failure(let error):
                    print("[AudiobookPlayerView] ❌ ERROR acquiring publication:", error)
                }
            } catch {
                print("[AudiobookPlayerView] ❌ ERROR loading license:", error)
            }
        }
    }

    func loadAudiobook(
        url: String,
        location: NSDictionary?,
        lcpPassphrase: String?
    ) {
        print("[AudiobookPlayerView] 🚀 loadAudiobook called (direct)")
        guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else {
            print("[AudiobookPlayerView] ❌ ERROR: No root view controller found")
            return
        }

        guard let readerService = self.readerService else {
            print("[AudiobookPlayerView] ❌ ERROR: ReaderService not initialized")
            return
        }

        print("[AudiobookPlayerView] ✅ Root view controller found, calling buildViewController")
        readerService.buildViewController(
            url: url,
            bookId: url,
            location: location,
            lcpPassphrase: lcpPassphrase,
            sender: rootViewController,
            completion: { vc in
                print("[AudiobookPlayerView] 🎉 buildViewController completion called")
                if let audiobookVC = vc as? AudiobookViewController {
                    print("[AudiobookPlayerView] ✅ Got AudiobookViewController, adding as subview")
                    self.addViewControllerAsSubview(audiobookVC)
                } else {
                    print("[AudiobookPlayerView] ❌ ERROR: Expected AudiobookViewController but got:", type(of: vc))
                }
            }
        )
    }

    override func removeFromSuperview() {
        audiobookViewController?.willMove(toParent: nil)
        audiobookViewController?.view.removeFromSuperview()
        audiobookViewController?.removeFromParent()

        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = Set<AnyCancellable>()

        audiobookViewController = nil
        super.removeFromSuperview()
    }

    private func addViewControllerAsSubview(_ vc: AudiobookViewController) {
        print("[AudiobookPlayerView] 📲 addViewControllerAsSubview called")

        vc.publisher.sink(
            receiveValue: { locator in
                print("[AudiobookPlayerView] 📍 Location changed:", locator.json)
                self.onLocationChange?(locator.json)
            }
        )
        .store(in: &self.subscriptions)

        audiobookViewController = vc

        guard
            audiobookViewController != nil,
            superview?.frame != nil,
            self.viewController != nil,
            self.audiobookViewController != nil
        else {
            print("[AudiobookPlayerView] ❌ ERROR: Prerequisites not met for adding subview")
            print("[AudiobookPlayerView]   - audiobookViewController: \(audiobookViewController != nil)")
            print("[AudiobookPlayerView]   - superview?.frame: \(superview?.frame != nil)")
            print("[AudiobookPlayerView]   - viewController: \(self.viewController != nil)")
            return
        }

        print("[AudiobookPlayerView] ✅ All prerequisites met, adding subview")
        audiobookViewController!.view.frame = superview!.frame
        self.viewController!.addChild(audiobookViewController!)
        let rootView = self.audiobookViewController!.view!
        self.addSubview(rootView)
        self.viewController!.addChild(audiobookViewController!)
        self.audiobookViewController!.didMove(toParent: self.viewController!)

        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        rootView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        rootView.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
        rootView.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true

        print("[AudiobookPlayerView] ✅ Subview added successfully")
    }
}
