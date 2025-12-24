import Combine
import Foundation
import ReadiumShared

final class Paths {
  private init() {}

  static let home: URL =
    URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

  static let temporary: URL =
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

  static let documents: URL =
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

  static let samples = Bundle.main.resourceURL!.appendingPathComponent("Samples")

  static let library: URL =
    FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!

  static let covers: URL = {
    let url = library.appendingPathComponent("Covers")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  static func makeDocumentURL(for source: URL? = nil, title: String?, mediaType: MediaType) -> AnyPublisher<URL, Never> {
    Future(on: .global()) { promise in
      // Is the file already in Documents/?
      if let source = source, source.standardizedFileURL.deletingLastPathComponent() == documents.standardizedFileURL {
        promise(.success(source))
      } else {
        let title = title.takeIf { !$0.isEmpty } ?? UUID().uuidString
        // MediaType no longer has fileExtension, so we extract from the media type string
        let ext = Self.fileExtension(for: mediaType)
        let filename = "\(title)\(ext)".sanitizedPathComponent
        let uniqueURL = documents.appendingPathComponent(filename + "_" + UUID().uuidString)
        promise(.success(uniqueURL))
      }
    }.eraseToAnyPublisher()
  }

  private static func fileExtension(for mediaType: MediaType) -> String {
    // Common media type to file extension mappings
    switch mediaType {
    case .epub: return ".epub"
    case .pdf: return ".pdf"
    case .cbz: return ".cbz"
    case .divina: return ".divina"
    case .lcpProtectedPDF: return ".lcpdf"
    case .lcpProtectedAudiobook: return ".audiobook"
    default: return ""
    }
  }

  static func makeTemporaryURL() -> AnyPublisher<URL, Never> {
    Future(on: .global()) { promise in
      let uniqueURL = temporary.appendingPathComponent(UUID().uuidString)
      promise(.success(uniqueURL))
    }.eraseToAnyPublisher()
  }

  /// Returns whether the given `url` locates a file that is under the app's home directory.
  static func isAppFile(at url: URL) -> Bool {
    url.path.hasPrefix(home.path)
  }
}
