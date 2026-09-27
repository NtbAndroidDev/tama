import AppKit
import Darwin

/// A private window-server space that sits above every desktop.
///
/// `.canJoinAllSpaces` + `.stationary` still leaves a window on the user's
/// desktops, so every Space switch drags it through the slide transition and it
/// visibly "snaps back" onto the notch. Windows moved into their own space at a
/// high absolute level are left out of that transition entirely — the same trick
/// other notch apps use. The SkyLight symbols are resolved at runtime; if any is
/// missing the window simply stays where AppKit put it.
@MainActor
final class SystemSpace {
    private typealias ConnectionID = Int32
    private typealias SpaceID = UInt64

    private typealias DefaultConnectionFn = @convention(c) () -> ConnectionID
    private typealias SpaceCreateFn = @convention(c) (ConnectionID, Int32, CFDictionary?) -> SpaceID
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (ConnectionID, SpaceID, Int32) -> Int32
    private typealias SpaceGetAbsoluteLevelFn = @convention(c) (ConnectionID, SpaceID) -> Int32
    private typealias SpacesFn = @convention(c) (ConnectionID, CFArray) -> Int32
    private typealias WindowsSpacesFn = @convention(c) (ConnectionID, CFArray, CFArray) -> Int32

    private let connection: ConnectionID
    private let space: SpaceID
    private let addWindows: WindowsSpacesFn

    init?(level: Int32 = Int32.max) {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return nil
        }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            guard let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }
        guard let defaultConnection = symbol("SLSMainConnectionID", as: DefaultConnectionFn.self),
              let create = symbol("SLSSpaceCreate", as: SpaceCreateFn.self),
              let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevelFn.self),
              let show = symbol("SLSShowSpaces", as: SpacesFn.self),
              let add = symbol("SLSAddWindowsToSpaces", as: WindowsSpacesFn.self)
        else { return nil }

        connection = defaultConnection()
        space = create(connection, 1, nil)
        guard space != 0 else {
            DroppyLog.error("SystemSpace", "SLSSpaceCreate returned 0")
            return nil
        }
        addWindows = add
        let levelResult = setLevel(connection, space, level)
        let showResult = show(connection, [NSNumber(value: space)] as CFArray)
        let readBack = symbol("SLSSpaceGetAbsoluteLevel", as: SpaceGetAbsoluteLevelFn.self)
            .map { $0(connection, space) } ?? -1
        DroppyLog.info("SystemSpace",
                       "space=\(space) cid=\(connection) setAbsoluteLevel(\(level))=\(levelResult) "
                       + "readBack=\(readBack) showSpaces=\(showResult)")
    }

    /// The window must already have a window number (i.e. have been ordered in).
    func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else {
            DroppyLog.error("SystemSpace", "window has no window number yet")
            return
        }
        let result = addWindows(
            connection,
            [NSNumber(value: window.windowNumber)] as CFArray,
            [NSNumber(value: space)] as CFArray
        )
        DroppyLog.info("SystemSpace",
                       "addWindowsToSpaces(win=\(window.windowNumber), space=\(space))=\(result) level=\(window.level.rawValue)")
    }
}
