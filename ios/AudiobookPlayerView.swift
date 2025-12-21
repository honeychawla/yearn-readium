import Combine
import Foundation
import R2Shared
import R2Streamer
import UIKit

class AudiobookPlayerView: UIView, Loggable {
    var readerService: ReaderService = ReaderService()
    var audiobookViewController: AudiobookViewController?
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
            if let url = file?["url"] as? String {
                print("[AudiobookPlayerView] 🎧 Loading audiobook from URL: \(url)")
                print("[AudiobookPlayerView] 🔐 Has passphrase: \(lcpPassphrase != nil)")
                if let passphrase = lcpPassphrase {
                    print("[AudiobookPlayerView] 🔐 Passphrase length: \(passphrase.count)")
                }
                self.loadAudiobook(url: url, location: initialLocation, lcpPassphrase: lcpPassphrase)
            } else {
                print("[AudiobookPlayerView] ❌ ERROR: No URL provided in file prop")
            }
        }
    }

    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onPlaybackStateChange: RCTDirectEventBlock?

    func loadAudiobook(
        url: String,
        location: NSDictionary?,
        lcpPassphrase: String?
    ) {
        print("[AudiobookPlayerView] 🚀 loadAudiobook called")
        guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else {
            print("[AudiobookPlayerView] ❌ ERROR: No root view controller found")
            return
        }

        print("[AudiobookPlayerView] ✅ Root view controller found, calling buildViewController")
        self.readerService.buildViewController(
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
