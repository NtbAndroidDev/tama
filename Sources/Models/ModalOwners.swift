import Foundation

/// Who is holding the island open, by name.
///
/// A set, not a Bool: several surfaces can hold at once, and whichever lets go
/// first must not clear the others' hold — auto-collapse would then tear a
/// sheet down mid-task, or close the shelf over a half-typed line. Owners name
/// the surface, not the sheet or the field, and a surface that can be on screen
/// more than once (a Basket) folds its id into its own name.
public struct OwnerSet: Equatable {
    private var owners: Set<String> = []

    public init() {}

    public var isPresenting: Bool { !owners.isEmpty }

    /// Marks a hold as taken or released for one owner. Idempotent, so a
    /// surface can simply restate what it has on screen whenever its state
    /// changes.
    public mutating func set(_ presented: Bool, owner: String) {
        if presented { owners.insert(owner) } else { owners.remove(owner) }
    }

    /// Drops every owner whose name starts with `prefix`. A surface that goes
    /// away still holding (a Basket closed from its own close button, a droplet
    /// console dismantled with its field focused) would otherwise hold the
    /// island open for good.
    public mutating func clear(withPrefix prefix: String) {
        owners = owners.filter { !$0.hasPrefix(prefix) }
    }
}

/// Who currently has a modal up over the island: the Tray page, each floating
/// Basket, a service alert.
public typealias ModalOwners = OwnerSet

/// Who is currently typing into the shelf: the Calendar's new-task field, a
/// droplet console's search box or editor. The shelf can't collapse under a
/// half-typed line, and closing it would reset the page and drop the draft.
public typealias EditingOwners = OwnerSet
