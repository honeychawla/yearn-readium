import Foundation
import R2Navigator
import R2Shared
import Combine

/// Manages user decorations (highlights, annotations) for the reader
@available(iOS 13.0, *)
class DecorationManager {

    /// Published array of user decorations
    @Published private(set) var userDecorations: [Decoration] = []

    /// Apply decorations from JavaScript
    func applyDecorations(_ decorations: [Decoration]) {
        print("DecorationManager: Applying \(decorations.count) decorations")
        self.userDecorations = decorations
    }

    /// Add a single decoration
    func addDecoration(_ decoration: Decoration) {
        userDecorations.append(decoration)
    }

    /// Remove a decoration by ID
    func removeDecoration(id: String) {
        userDecorations.removeAll { $0.id == id }
    }

    /// Clear all decorations
    func clearDecorations() {
        userDecorations.removeAll()
    }
}
