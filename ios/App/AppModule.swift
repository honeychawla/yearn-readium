import Combine
import Foundation
import UIKit
import ReadiumShared
import ReadiumStreamer
import ReadiumLCP
import ReadiumAdapterLCPSQLite
import ReadiumAdapterGCDWebServer


/// Base module delegate, that sub-modules' delegate can extend.
/// Provides basic shared functionalities.
protocol ModuleDelegate: AnyObject {
  func presentAlert(_ title: String, message: String, from viewController: UIViewController)
  func presentError(_ error: Error?, from viewController: UIViewController)
}


/// Main application module, it:
/// - owns the sub-modules (reader, etc.)
/// - orchestrates the communication between its sub-modules, through the modules' delegates.
final class AppModule {

  // App modules
  var reader: ReaderModuleAPI! = nil

  // LCP service
  var lcpService: LCPService?

  // HTTP server for serving publication resources
  var httpServer: GCDHTTPServer

  init() throws {
    // Initialize shared components
    let httpClient = DefaultHTTPClient()
    let assetRetriever = AssetRetriever(httpClient: httpClient)

    // Initialize HTTP server for EPUB resources (starts automatically when needed)
    httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
    print("[HTTPServer] Initialized (will start when serving publications)")

    // Initialize LCP service with SQLite repositories
    let lcpClient = LCPClientImpl()

    lcpService = LCPService(
      client: lcpClient,
      licenseRepository: try LCPSQLiteLicenseRepository(),
      passphraseRepository: try LCPSQLitePassphraseRepository(),
      assetRetriever: assetRetriever,
      httpClient: httpClient
    )
    print("[LCP] Service initialized successfully")

    reader = ReaderModule(delegate: self, httpServer: httpServer)
  }
}


extension AppModule: ModuleDelegate {

  func presentAlert(_ title: String, message: String, from viewController: UIViewController) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    let dismissButton = UIAlertAction(title: NSLocalizedString("ok_button", comment: "Alert button"), style: .cancel)
    alert.addAction(dismissButton)
    viewController.present(alert, animated: true)
  }

  func presentError(_ error: Error?, from viewController: UIViewController) {
    guard let error = error else { return }
    if case ReaderError.cancelled = error { return }
    presentAlert(
      NSLocalizedString("error_title", comment: "Alert title for errors"),
      message: error.localizedDescription,
      from: viewController
    )
  }

}


extension AppModule: ReaderModuleDelegate {}
