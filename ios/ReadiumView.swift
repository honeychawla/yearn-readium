import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit
import ReadiumNavigator


class ReadiumView : UIView, Loggable {
  var readerService: ReaderService = ReaderService()
  var readerViewController: ReaderViewController?
  var viewController: UIViewController? {
    let viewController = sequence(first: self, next: { $0.next }).first(where: { $0 is UIViewController })
    return viewController as? UIViewController
  }
  private var subscriptions = Set<AnyCancellable>()

  @objc var file: NSDictionary? = nil {
    didSet {
      let initialLocation = file?["initialLocation"] as? NSDictionary
      let lcpPassphrase = file?["lcpPassphrase"] as? String
      if let url = file?["url"] as? String {
        self.loadBook(url: url, location: initialLocation, lcpPassphrase: lcpPassphrase)
      }
    }
  }
  @objc var location: NSDictionary? = nil {
    didSet {
      self.updateLocation()
    }
  }
  @objc var preferences: NSString? = nil {
    didSet {
      self.updatePreferences(preferences)
    }
  }
  @objc var decorations: NSString? = nil {
    didSet {
      self.updateDecorations(decorations)
    }
  }
  @objc var onLocationChange: RCTDirectEventBlock?
  @objc var onTableOfContents: RCTDirectEventBlock?
  @objc var onDecorationTapped: RCTDirectEventBlock?
  @objc var onTextSelected: RCTDirectEventBlock?

  func loadBook(
    url: String,
    location: NSDictionary?,
    lcpPassphrase: String?
  ) {
    guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else { return }

    self.readerService.buildViewController(
      url: url,
      bookId: url,
      location: location,
      lcpPassphrase: lcpPassphrase,
      sender: rootViewController,
      completion: { vc in
        self.addViewControllerAsSubview(vc)
        self.location = location
      }
    )
  }

  func getLocator() -> Locator? {
    return ReaderService.locatorFromLocation(location, readerViewController?.publication)
  }

  func updateLocation() {
    guard let navigator = readerViewController?.navigator else {
      return;
    }
    guard let locator = self.getLocator() else {
      return;
    }

    let cur = navigator.currentLocation
    if (cur != nil && locator.hashValue == cur?.hashValue) {
      return;
    }

    Task {
      await navigator.go(to: locator)
    }
  }

  func updatePreferences(_ preferences: NSString?) {

    if (readerViewController == nil) {
      // defer setting update as view isn't initialized yet
      return;
    }

    guard let navigator = readerViewController!.navigator as? EPUBNavigatorViewController else {
      return;
    }

    guard let preferencesJson = preferences as? String else {
      print("TODO: handle error. Bad string conversion for preferences")
      return;
    }

    do {
      let preferences = try JSONDecoder().decode(EPUBPreferences.self, from: Data(preferencesJson.utf8))
      navigator.submitPreferences(preferences)
    } catch {
      print(error)
      print("TODO: handle error. Skipping preferences due to thrown exception")
      return;
    }
  }

  func updateDecorations(_ decorations: NSString?) {
    guard decorations != nil else {
      return
    }

    guard let epubVC = readerViewController as? EPUBViewController else {
      print("ReadiumView: ReaderViewController is not EPUBViewController, skipping decorations")
      return
    }

    guard let decorationsJson = decorations as? String else {
      print("ReadiumView: Bad string conversion for decorations")
      return
    }

    let parsedDecorations = parseDecorationsFromJSON(decorationsJson)
    print("ReadiumView: Applying \(parsedDecorations.count) decorations")
    epubVC.decorationManager.applyDecorations(parsedDecorations)
  }

  private func parseDecorationsFromJSON(_ json: String) -> [Decoration] {
    guard let data = json.data(using: .utf8),
          let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      print("ReadiumView: Failed to parse decorations JSON")
      return []
    }

    var decorations: [Decoration] = []

    for obj in jsonArray {
      guard let id = obj["id"] as? String,
            let locatorDict = obj["locator"] as? [String: Any],
            let styleDict = obj["style"] as? [String: Any],
            let styleType = styleDict["type"] as? String else {
        continue
      }

      // Parse locator from JSON
      guard let locator = try? Locator(json: locatorDict) else {
        print("ReadiumView: Failed to parse locator")
        continue
      }

      // Parse color (default to yellow)
      let colorHex = styleDict["color"] as? String ?? "#FFFF00"
      let color = UIColor(hex: colorHex) ?? .yellow

      // Create decoration style
      let style: Decoration.Style
      if styleType == "underline" {
        style = Decoration.Style.underline(tint: color)
      } else {
        style = Decoration.Style.highlight(tint: color, isActive: false)
      }

      decorations.append(Decoration(id: id, locator: locator, style: style))
    }

    return decorations
  }

  override func removeFromSuperview() {
    readerViewController?.willMove(toParent: nil)
    readerViewController?.view.removeFromSuperview()
    readerViewController?.removeFromParent()

    // cancel all current subscriptions
    for subscription in subscriptions {
      subscription.cancel()
    }
    subscriptions = Set<AnyCancellable>()

    readerViewController = nil
    super.removeFromSuperview()
  }

  private func addViewControllerAsSubview(_ vc: ReaderViewController) {
    vc.publisher.sink(
      receiveValue: { locator in
        self.onLocationChange?(locator.json)
      }
    )
    .store(in: &self.subscriptions)

    readerViewController = vc

    // if the controller was just instantiated then apply any existing preferences
    if (preferences != nil) {
      self.updatePreferences(preferences)
    }

    guard
      readerViewController != nil,
      superview?.frame != nil,
      self.viewController != nil,
      self.readerViewController != nil
    else {
      return
    }

    readerViewController!.view.frame = superview!.frame
    self.viewController!.addChild(readerViewController!)
    let rootView = self.readerViewController!.view!
    self.addSubview(rootView)
    self.viewController!.addChild(readerViewController!)
    self.readerViewController!.didMove(toParent: self.viewController!)

    // bind the reader's view to be constrained to its parent
    rootView.translatesAutoresizingMaskIntoConstraints = false
    rootView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
    rootView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
    rootView.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
    rootView.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true

    Task {
      let toc = await vc.publication.tableOfContents()
      await MainActor.run {
        self.onTableOfContents?([
          "toc": toc.map({ link in
            return link.json
          })
        ])
      }
    }

    // Apply decorations if they were set before view controller was ready
    if decorations != nil {
      updateDecorations(decorations)
    }
  }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
