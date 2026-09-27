import Foundation
import Testing
@testable import Droppy

@Suite struct ModalOwnersTests {
    @Test func oneOwnerPresentsAndClears() {
        var owners = ModalOwners()
        #expect(!owners.isPresenting)
        owners.set(true, owner: "tray.page")
        #expect(owners.isPresenting)
        owners.set(false, owner: "tray.page")
        #expect(!owners.isPresenting)
    }

    /// The bug this type exists for: a Basket closing its preview used to
    /// clear the flag while the Tray still had one up, so the island could
    /// auto-collapse out from under an open sheet.
    @Test func oneOwnerClosingLeavesAnotherPresenting() {
        var owners = ModalOwners()
        owners.set(true, owner: "tray.page")
        owners.set(true, owner: "basket.A")
        owners.set(false, owner: "basket.A")
        #expect(owners.isPresenting)
        owners.set(false, owner: "tray.page")
        #expect(!owners.isPresenting)
    }

    @Test func settingTheSameOwnerTwiceIsNotCounted() {
        var owners = ModalOwners()
        owners.set(true, owner: "tray.page")
        owners.set(true, owner: "tray.page")
        owners.set(false, owner: "tray.page")
        #expect(!owners.isPresenting)
    }

    @Test func clearingAPrefixDropsOnlyThatSurface() {
        var owners = ModalOwners()
        owners.set(true, owner: "basket.A")
        owners.set(true, owner: "basket.B")
        owners.set(true, owner: "tray.page")
        owners.clear(withPrefix: "basket.A")
        #expect(owners.isPresenting)
        owners.clear(withPrefix: "basket.")
        #expect(owners.isPresenting)
        owners.clear(withPrefix: "tray.")
        #expect(!owners.isPresenting)
    }

    @Test func clearingAnUnknownPrefixChangesNothing() {
        var owners = ModalOwners()
        owners.set(true, owner: "tray.page")
        owners.clear(withPrefix: "basket.")
        #expect(owners.isPresenting)
    }
}
