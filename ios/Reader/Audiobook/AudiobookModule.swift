import Foundation
import UIKit
import ReadiumShared

final class AudiobookModule: ReaderFormatModule {

    weak var delegate: ReaderFormatModuleDelegate?

    init(delegate: ReaderFormatModuleDelegate?) {
        self.delegate = delegate
    }

    func supports(_ publication: Publication) -> Bool {
        // Check if publication conforms to audiobook profile
        return publication.conforms(to: .audiobook)
    }

    func makeReaderViewController(
        for publication: Publication,
        locator: Locator?,
        bookId: String
    ) throws -> ReaderViewController {
        guard publication.metadata.identifier != nil else {
            throw ReaderError.epubNotValid // TODO: Create audiobookNotValid error
        }

        let audiobookViewController = try AudiobookViewController(
            publication: publication,
            locator: locator,
            bookId: bookId
        )
        audiobookViewController.moduleDelegate = delegate
        return audiobookViewController
    }
}
