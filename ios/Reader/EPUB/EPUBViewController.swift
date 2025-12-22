import UIKit
import ReadiumShared
import ReadiumNavigator
import ReadiumAdapterGCDWebServer
import Combine

class EPUBViewController: ReaderViewController {

    // Decoration manager for highlights
    let decorationManager = DecorationManager()
    private var decorationCancellable: AnyCancellable?

    init(
      publication: Publication,
      locator: Locator?,
      bookId: String,
      httpServer: GCDHTTPServer
    ) throws {
      // Create configuration with custom editing actions
      var config = EPUBNavigatorViewController.Configuration()
      config.editingActions.append(EditingAction(
        title: "Highlight",
        action: #selector(EPUBViewController.handleHighlightAction(_:))
      ))

      let navigator = try EPUBNavigatorViewController(
        publication: publication,
        initialLocation: locator,
        config: config,
        httpServer: httpServer
      )

      super.init(
        navigator: navigator,
        publication: publication,
        bookId: bookId
      )

      navigator.delegate = self
    }

    var epubNavigator: EPUBNavigatorViewController {
      return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
      super.viewDidLoad()

      /// Set initial UI appearance.
      setUIColor(for: epubNavigator.settings.theme)

      // Become first responder to receive menu actions
      becomeFirstResponder()

      // Observe decoration changes and apply to navigator
      if #available(iOS 13.0, *) {
        decorationCancellable = decorationManager.$userDecorations
          .sink { [weak self] decorations in
            guard let self = self,
                  let decorableNavigator = self.navigator as? DecorableNavigator else { return }

            print("EPUBViewController: Applying \(decorations.count) decorations to navigator")
            decorableNavigator.apply(decorations: decorations, in: "user-highlights")
          }
      }

      // Setup text selection handler
      setupTextSelection()

      // Setup decoration tap observer
      setupDecorationObserver()
    }

    deinit {
      decorationCancellable?.cancel()
    }

    internal func setUIColor(for theme: Theme) {
      let colors = AssociatedColors.getColors(for: theme)

      navigator.view.backgroundColor = colors.mainColor
      view.backgroundColor = colors.mainColor
      //
      navigationController?.navigationBar.barTintColor = colors.mainColor
      navigationController?.navigationBar.tintColor = colors.textColor

      navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: colors.textColor]
    }

    override var currentBookmark: Bookmark? {
      guard let locator = navigator.currentLocation else {
        return nil
      }

      return Bookmark(bookId: bookId, locator: locator)
    }

}

extension EPUBViewController: EPUBNavigatorDelegate {

    // Allow the default menu to show - it will include our custom Highlight action
    func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
        NSLog("📝 shouldShowMenuForSelection called - showing menu")
        return true // Show the default menu with our Highlight action
    }
}

// MARK: - Highlights & Text Selection

extension EPUBViewController {

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(handleHighlightAction(_:)) {
            NSLog("🔥 canPerformAction: YES for handleHighlightAction")
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    fileprivate func setupTextSelection() {
        // Text selection is configured in the init with editingActions
        // The handleHighlightAction method is called when user taps "Highlight"
        print("EPUBViewController: Text selection configured with Highlight action")
    }

    @objc func handleHighlightAction(_ sender: Any) {
        NSLog("🎯🎯🎯 HIGHLIGHT ACTION TRIGGERED!!!")
        print("EPUBViewController: Highlight action triggered")

        guard let selectableNavigator = navigator as? SelectableNavigator else {
            print("EPUBViewController: Navigator is not SelectableNavigator")
            return
        }

        Task { @MainActor in
            guard let selection = await selectableNavigator.currentSelection else {
                print("EPUBViewController: No current selection")
                return
            }

            // Extract selected text
            let selectedText = selection.locator.text.highlight ?? ""
            print("EPUBViewController: Selected text: \(selectedText)")

            // Send to JavaScript - find ReadiumView in view hierarchy
            var readiumView: ReadiumView? = nil
            var currentView = self.view.superview
            while currentView != nil {
                if let found = currentView as? ReadiumView {
                    readiumView = found
                    break
                }
                currentView = currentView?.superview
            }

            guard let readiumView = readiumView else {
                print("EPUBViewController: Could not find ReadiumView")
                return
            }

            let locatorJson: [String: Any] = selection.locator.json
            let eventData: [String: Any] = [
                "selectedText": selectedText,
                "locator": locatorJson
            ]

            readiumView.onTextSelected?(eventData)

            // Clear the selection after creating highlight
            await selectableNavigator.clearSelection()
            print("EPUBViewController: Selection cleared")
        }
    }

    fileprivate func setupDecorationObserver() {
        // TODO: Update to Readium 2.6.0 decoration observer API
        // The observe() method API has changed in newer versions
        print("EPUBViewController: Decoration observer not yet implemented for Readium 2.6.0")
    }

    fileprivate func handleDecorationTap(_ decoration: Decoration) {
        // Send decoration tap event to JavaScript
        guard let parentVC = parent as? ReadiumView else { return }

        // TODO: Update to Readium 2.6.0 Decoration.Style API
        let styleString = "highlight" // Default for now

        let eventData: [String: Any] = [
            "decorationId": decoration.id,
            "locator": decoration.locator.json,
            "style": styleString
        ]

        parentVC.onDecorationTapped?(eventData)
    }
}

extension EPUBViewController: UIGestureRecognizerDelegate {

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    return true
  }

}

extension EPUBViewController: UIPopoverPresentationControllerDelegate {
  // Prevent the popOver to be presented fullscreen on iPhones.
  func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
  {
    return .none
  }
}
