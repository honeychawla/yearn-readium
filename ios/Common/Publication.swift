import CoreServices
import Foundation
import ReadiumShared

extension Publication {

  /// Finds all the downloadable links for this publication.
  var downloadLinks: [Link] {
    links.filter {
      let mediaTypeString = $0.mediaType?.string
      let fileExtension = $0.url().pathExtension?.rawValue
      return DocumentTypes.main.supportsMediaType(mediaTypeString)
        || DocumentTypes.main.supportsFileExtension(fileExtension)
    }
  }

}
