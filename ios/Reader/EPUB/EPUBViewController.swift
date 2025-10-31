import UIKit
import R2Shared
import R2Navigator
import ReadiumAdapterGCDWebServer
import Combine

class EPUBViewController: ReaderViewController {

    // Decoration manager for highlights
    let decorationManager = DecorationManager()
    private var decorationCancellable: AnyCancellable?

    init(
      publication: Publication,
      locator: Locator?,
      bookId: String
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
        httpServer: GCDHTTPServer.shared
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

extension EPUBViewController: EPUBNavigatorDelegate {}

// MARK: - Highlights & Text Selection

extension EPUBViewController {

    fileprivate func setupTextSelection() {
        // Text selection is configured in the init with editingActions
        // The handleHighlightAction method is called when user taps "Highlight"
        print("EPUBViewController: Text selection configured with Highlight action")
    }

    @objc fileprivate func handleHighlightAction(_ sender: Any) {
        print("EPUBViewController: Highlight action triggered")

        guard let selectableNavigator = navigator as? SelectableNavigator else {
            print("EPUBViewController: Navigator is not SelectableNavigator")
            return
        }

        Task {
            guard let selection = await selectableNavigator.currentSelection else {
                print("EPUBViewController: No current selection")
                return
            }

            // Extract selected text
            let selectedText = selection.locator.text.highlight ?? ""
            print("EPUBViewController: Selected text: \(selectedText)")

            // Send to JavaScript
            guard let parentVC = parent as? ReadiumView else { return }

            let eventData: [String: Any] = [
                "selectedText": selectedText,
                "locator": selection.locator.json
            ]

            parentVC.onTextSelected?(eventData)

            // Clear the selection after creating highlight
            selectableNavigator.clearSelection()
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
