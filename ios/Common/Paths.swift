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
        let ext = (mediaType.fileExtension.map { ".\($0)" }) ?? ""
        let filename = "\(title)\(ext)".sanitizedPathComponent
        let uniqueURL = documents.appendingPathComponent(filename + "_" + UUID().uuidString)
        promise(.success(uniqueURL))
      }
    }.eraseToAnyPublisher()
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
