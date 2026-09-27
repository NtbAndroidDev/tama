import AppKit
import Foundation
import Testing
@testable import Droppy

@Suite struct Phase9bTests {
    // MARK: Shortcuts

    @Test @MainActor func widgetShortcutsAreSettingsAndStartEmpty() {
        let keys = Set(AppState.settingsKeys)
        #expect(keys.count == AppState.settingsKeys.count, "settings keys must be unique")
        for droplet in AppState.defaultDroplets {
            let slot = ShortcutSlot.droplet(droplet.id)
            #expect(keys.contains(slot.defaultsKey))
            #expect(GlobalShortcutService.shared.defaultCombo(for: slot) == nil)
        }
        for action in [ShortcutAction.quickRecord, .menuBarToggle] {
            #expect(GlobalShortcutService.shared.defaultCombo(for: action) == nil)
        }
        let slotKeys = ShortcutSlot.all.map(\.defaultsKey)
        #expect(Set(slotKeys).count == slotKeys.count)
        #expect(keys.contains("voiceRetention") && keys.contains("menuBarAlwaysHidden") && keys.contains("thunderstormInlineAnswers"))
    }

    @Test @MainActor func widgetShortcutConflictsAreReported() {
        let service = GlobalShortcutService.shared
        let combo = KeyCombo(keyCode: 0x2F, modifiers: 0x0800 | 0x1000) // ⌃⌥. — unused by defaults
        defer {
            service.resetCombo(for: .droplet("timer"))
            service.resetCombo(for: .droplet("weather"))
        }
        #expect(service.setCombo(combo, for: .droplet("timer")) == nil)
        #expect(service.combo(for: .droplet("timer")) == combo)
        #expect(service.setCombo(combo, for: .droplet("weather")) == .droplet("timer"))
        #expect(service.combo(for: .droplet("weather")) == nil)
        service.resetAll()
        #expect(service.combo(for: .droplet("timer")) == nil)
    }

    @Test func everyActionHasAGroup() {
        #expect(ShortcutAction.thunderstorm.group == .tools)
        #expect(ShortcutAction.quickRecord.dropletID == "voiceTranscribe")
        #expect(ShortcutAction.snapLeftHalf.dropletID == "windowSnapper")
        #expect(AppState.defaultDroplets.contains { $0.id == "menuBar" && !$0.isEnabled })
    }

    // MARK: Search

    @Test @MainActor func settingsAnchorsAreUnique() {
        let anchors = SettingsSearchIndex.entries.map(\.anchor)
        #expect(Set(anchors).count == anchors.count)
        #expect(SettingsSearchIndex.search("quick record").contains { $0.anchor == "droplet.voiceTranscribe.quickRecord" })
        #expect(SettingsSearchIndex.search("reset all shortcuts").first?.page == .shortcuts)
    }

    @Test func launcherMatchingRanksTitlePrefixes() throws {
        let exact = try #require(LauncherMatch.score("sleep", title: "Sleep"))
        let prefix = try #require(LauncherMatch.score("shut", title: "Shut Down"))
        let keyword = try #require(LauncherMatch.score("reboot", title: "Restart", keywords: ["reboot"]))
        #expect(exact > prefix && prefix > keyword)
        #expect(LauncherMatch.score("zebra", title: "Restart") == nil)
        #expect(LauncherMatch.score("  ", title: "Restart") == nil)
    }

    @Test func systemSettingsPanesAreComplete() {
        let panes = SystemSettingsPane.all
        #expect(Set(panes.map(\.id)).count == panes.count)
        #expect(panes.allSatisfy { $0.url != nil })
        for name in ["Printers & Scanners", "Wallet & Apple Pay", "Touch ID & Password", "Internet Accounts",
                     "Language & Region", "Game Controllers", "Family", "Siri", "Keyboard Shortcuts"] {
            #expect(panes.contains { $0.name == name }, "\(name)")
        }
        #expect(panes.first { $0.name == "Screen Time" }?.detail == "App limits, downtime, and communication limits.")
        #expect(SystemCommand.restart.confirmation != nil && SystemCommand.lockScreen.confirmation == nil)
    }

    @Test func webSearchURLsEncodeTheQuery() {
        let url = WebSearchEngine.google.url(for: "swift & rust")?.absoluteString ?? ""
        #expect(url.hasPrefix("https://www.google.com/search?q="))
        #expect(url.contains("swift%20&%20rust") || url.contains("swift%20%26%20rust"))
        #expect(WebSearchEngine.wikipedia.url(for: "Mac")?.absoluteString == "https://en.wikipedia.org/w/index.php?search=Mac")
    }

    @Test func instantAnswersParse() {
        let answer = Data(#"{"Answer":"42","Heading":"","AbstractText":""}"#.utf8)
        #expect(InstantAnswerService.parse(answer)?.text == "42")
        let abstract = Data(#"{"Answer":"","Heading":"Swift","AbstractText":"A language.","AbstractSource":"Wikipedia","AbstractURL":"https://en.wikipedia.org/wiki/Swift"}"#.utf8)
        let parsed = InstantAnswerService.parse(abstract)
        #expect(parsed?.heading == "Swift" && parsed?.source == "Wikipedia" && parsed?.url != nil)
        #expect(InstantAnswerService.parse(Data(#"{"Answer":"","AbstractText":"","Definition":""}"#.utf8)) == nil)
        #expect(InstantAnswerService.parse(Data("not json".utf8)) == nil)
    }

    // MARK: Voice

    @Test func wordCountAndOldRecordingsDecode() throws {
        #expect(VoiceTranscribeService.wordCount("Hallo, hallo, hallo, hallo.") == 4)
        #expect(VoiceTranscribeService.wordCount("") == 0)
        let old = Data(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","fileName":"a.m4a","date":0,"duration":3,"transcript":"hi","localeID":"en-US"}]"#.utf8)
        let recordings = try JSONDecoder().decode([VoiceRecording].self, from: old)
        #expect(recordings.first?.hasAudio == true)
        var deleted = try #require(recordings.first)
        deleted.audioDeleted = true
        let roundTrip = try JSONDecoder().decode(VoiceRecording.self, from: JSONEncoder().encode(deleted))
        #expect(!roundTrip.hasAudio)
    }

    @Test func optionsRoundTrip() {
        for engine in VoiceEngine.allCases { #expect(VoiceEngine(rawValue: engine.rawValue) == engine) }
        for retention in VoiceRetention.allCases { #expect(VoiceRetention(rawValue: retention.rawValue) == retention) }
        for icon in MenuBarToggleIcon.allCases {
            #expect(NSImage(systemSymbolName: icon.symbol(revealed: true), accessibilityDescription: nil) != nil)
            #expect(NSImage(systemSymbolName: icon.symbol(revealed: false), accessibilityDescription: nil) != nil)
        }
        for pane in SystemSettingsPane.all {
            #expect(NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil) != nil, "\(pane.symbol)")
        }
        for command in SystemCommand.allCases {
            #expect(NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil) != nil, "\(command.symbol)")
        }
    }
}
