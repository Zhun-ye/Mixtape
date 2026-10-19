import Foundation

struct HomeResponse: Sendable {
    let sections: [HomeSection]
    let continuation: Continuation?

    /// Whether the home response is empty.
    var isEmpty: Bool {
        self.sections.isEmpty || self.sections.allSatisfy(\.items.isEmpty)
    }

    /// Whether more sections can be loaded.
    var hasMore: Bool {
        continuation != nil
    }

    static let empty = HomeResponse(sections: [], continuation: nil)

    /// Continuation state for loading more sections.
    struct Continuation: Sendable {
        let token: String
    }
}
