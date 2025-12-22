import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import ReadiumLCP
import UIKit

final class ReaderService: Loggable {
  var app: AppModule?
  var assetRetriever: AssetRetriever
  var publicationOpener: PublicationOpener?
  private var subscriptions = Set<AnyCancellable>()
  var lcpPassphrase: String? = nil

  init() {
    do {
      self.app = try AppModule()

      // Initialize AssetRetriever
      self.assetRetriever = AssetRetriever(httpClient: DefaultHTTPClient())
      print("[Readium] AssetRetriever initialized")
    } catch {
      print("TODO: An error occurred instantiating the ReaderService")
      print(error)
      self.assetRetriever = AssetRetriever(httpClient: DefaultHTTPClient())
    }
  }
  
  static func locatorFromLocation(
    _ location: NSDictionary?,
    _ publication: Publication?
  ) -> Locator? {
    guard location != nil else {
      return nil
    }

    let hasLocations = location?["locations"] != nil
    let hasType = (location?["type"] as? String)?.isEmpty == false
    let hasChildren = location?["children"] != nil
    let hasHashHref = (location?["href"] as? String)?.contains("#") == true
    let hasTemplated = location?["templated"] != nil

    // check that we're not dealing with a Link
    if ((!hasType || hasChildren || hasHashHref || hasTemplated) && !hasLocations) {
      guard let publication = publication else {
        return nil
      }
      guard let link = try? Link(json: location) else {
        return nil
      }

      // Note: locate() is async in Readium 3.x, but this function is sync
      // For now, just return the first locator for the link
      return publication.readingOrder.first(where: { $0.href == link.href }).map { publication.locator(from: $0) }
    } else {
      return try? Locator(json: location)
    }

    return nil
  }

  func buildViewController(
    url: String,
    bookId: String,
    location: NSDictionary?,
    lcpPassphrase: String?,
    sender: UIViewController?,
    completion: @escaping (ReaderViewController) -> Void
  ) {
    // Store the hashed passphrase for this book
    self.lcpPassphrase = lcpPassphrase

    // Create PublicationOpener with LCP authentication
    if let passphrase = lcpPassphrase, let lcpService = self.app?.lcpService {
      print("[LCP] ✅ Creating publication opener with automatic authentication")
      print("[LCP] Hashed passphrase: \(passphrase.prefix(16))...")

      let authentication = LCPPassphraseAuthentication(passphrase)

      self.publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
          httpClient: DefaultHTTPClient(),
          assetRetriever: assetRetriever,
          pdfFactory: DefaultPDFDocumentFactory()
        ),
        contentProtections: [lcpService.contentProtection(with: authentication)]
      )
    } else if let lcpService = self.app?.lcpService {
      print("[LCP] No passphrase - using dialog authentication")

      self.publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
          httpClient: DefaultHTTPClient(),
          assetRetriever: assetRetriever,
          pdfFactory: DefaultPDFDocumentFactory()
        ),
        contentProtections: [lcpService.contentProtection(with: LCPDialogAuthentication())]
      )
    }

    guard let reader = self.app?.reader else { return }

    Task {
      do {
        let fileURL = try self.getFileURL(path: url)
        let asset = try await self.retrieveAsset(at: fileURL)
        let publication = try await self.openPublication(asset: asset, sender: sender)

        guard !publication.isRestricted else {
          if let error = publication.protectionError {
            print(">>>>>>>>>>> Publication is restricted:", error)
          }
          return
        }

        await MainActor.run {
          let locator: Locator? = ReaderService.locatorFromLocation(location, publication)
          if let vc = reader.getViewController(for: publication, bookId: bookId, locator: locator) {
            completion(vc)
          }
        }
      } catch {
        print(">>>>>>>>>>> Error opening publication:", error)
      }
    }
  }

  private func getFileURL(path: String) throws -> FileURL {
    // Absolute URL
    if let url = URL(string: path), url.scheme != nil {
      guard let fileURL = FileURL(url: url) else {
        throw ReaderError.fileNotFound(NSError(domain: "ReaderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: " + path]))
      }
      return fileURL
    }

    // Absolute file path
    if path.hasPrefix("/") {
      guard let fileURL = FileURL(path: path) else {
        throw ReaderError.fileNotFound(NSError(domain: "ReaderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid file path: " + path]))
      }
      return fileURL
    }

    throw ReaderError.fileNotFound(NSError(domain: "ReaderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate file: " + path]))
  }

  private func retrieveAsset(at url: FileURL) async throws -> Asset {
    let result = await assetRetriever.retrieve(url: url)

    switch result {
    case .success(let asset):
      return asset
    case .failure(let error):
      throw ReaderError.openFailed(error)
    }
  }

  private func openPublication(asset: Asset, sender: UIViewController?) async throws -> Publication {
    guard let opener = publicationOpener else {
      throw ReaderError.openFailed(NSError(domain: "ReaderService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No publication opener"]))
    }

    let result = await opener.open(
      asset: asset,
      allowUserInteraction: false,
      sender: sender
    )

    switch result {
    case .success(let publication):
      print("[Publication] Opened successfully")
      return publication
    case .failure(let error):
      throw ReaderError.openFailed(error)
    }
  }
}
