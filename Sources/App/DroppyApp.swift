import SwiftUI

@main
public struct DroppyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    public init() {
        // Carries settings and stored files over from the old name. Must run
        // before any @AppStorage is read, so it lives here and not in
        // applicationDidFinishLaunching.
        _ = LegacyRename.run
    }
    
    public var body: some Scene {
        // We use custom NSPanels managed in AppDelegate/NotchWindowController.
        // The Settings scene is empty and its menu item is rerouted, so ⌘, opens
        // the one real Settings window rather than a second SwiftUI copy.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindowController.shared.showWindow() }
                    .keyboardShortcut(",")
            }
        }
    }
}
