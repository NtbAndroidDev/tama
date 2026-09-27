import Foundation

/// Where the keyboard should land when the row it was on disappears.
///
/// Lists that can lose a row without the keyboard asking — a clip deleted from
/// its own menu, a Tray file that expired or was trashed in Finder — used to
/// drop the focus back to the front of the list. That scrolls the list out
/// from under the person, and the next Delete then takes a row they never
/// meant to touch. Stepping to the neighbour keeps their place instead.
enum FocusAfterRemoval {
    /// The id nearest `gone` that is still there: the one after it, else the
    /// one before. nil when `order` never held it, or nothing survived.
    static func next(after gone: UUID, in order: [UUID], surviving: Set<UUID>) -> UUID? {
        guard let index = order.firstIndex(of: gone) else { return nil }
        return order[(index + 1)...].first(where: surviving.contains)
            ?? order[..<index].last(where: surviving.contains)
    }
}
