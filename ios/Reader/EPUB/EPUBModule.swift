import Foundation
import UIKit
import ReadiumShared


import ReadiumAdapterGCDWebServer

final class EPUBModule: ReaderFormatModule {

    weak var delegate: ReaderFormatModuleDelegate?
    let httpServer: GCDHTTPServer

    init(delegate: ReaderFormatModuleDelegate?, httpServer: GCDHTTPServer) {
        self.delegate = delegate
        self.httpServer = httpServer
    }

    func supports(_ publication: Publication) -> Bool {
      publication.conforms(to: .epub)
        || publication.readingOrder.allAreHTML
    }

    func makeReaderViewController(
      for publication: Publication,
      locator: Locator?,
      bookId: String
    ) throws -> ReaderViewController {
        guard publication.metadata.identifier != nil else {
            throw ReaderError.epubNotValid
        }

        let epubViewController = try EPUBViewController(
            publication: publication,
            locator: locator,
            bookId: bookId,
            httpServer: httpServer
        )
        epubViewController.moduleDelegate = delegate
        return epubViewController
    }

}
