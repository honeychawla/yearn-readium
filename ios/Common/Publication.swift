import CoreServices
import Foundation
import ReadiumShared

extension Publication {

  /// Finds all the downloadable links for this publication.
  var downloadLinks: [Link] {
    links.filter {
      return DocumentTypes.main.supportsMediaType($0.mediaType)
        || DocumentTypes.main.supportsFileExtension($0.url().fileExtension)
    }
  }

}
