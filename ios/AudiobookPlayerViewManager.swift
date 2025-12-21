import Foundation

@objc(AudiobookPlayerViewManager)
class AudiobookPlayerViewManager: RCTViewManager {

  override init() {
    super.init()
    print("[AudiobookPlayerViewManager] ✅ Manager initialized!")
  }

  override func view() -> (AudiobookPlayerView) {
    print("[AudiobookPlayerViewManager] ✅ view() called - creating AudiobookPlayerView")
    let view = AudiobookPlayerView()
    return view
  }

  override static func requiresMainQueueSetup() -> Bool {
    print("[AudiobookPlayerViewManager] ✅ requiresMainQueueSetup called")
    return true
  }
}
