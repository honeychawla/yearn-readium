import Foundation

@objc(ReadiumViewManager)
class ReadiumViewManager: RCTViewManager {
  override func view() -> (ReadiumView) {
    let view = ReadiumView()
    return view
  }

  override static func requiresMainQueueSetup() -> Bool {
    return true
  }
}
