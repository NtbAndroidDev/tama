import Foundation
import Testing
@testable import Droppy

/// The guide is written by hand, so the things a typo would break quietly —
/// a Settings link that lands nowhere, an article that can't be found by its
/// own words — are checked here instead of in the app.
@Suite struct UserGuideTests {

    @Test func everyArticleHasAnIdOfItsOwn() {
        let ids = DroppyGuide.articles.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.isEmpty)
    }

    @Test func everyCategoryHasSomethingInIt() {
        for category in GuideCategory.allCases {
            #expect(!DroppyGuide.articles(in: category).isEmpty, "\(category.rawValue) is empty")
        }
    }

    /// Every "Open in Settings" link has to name a row the Settings index
    /// knows, or the button opens Settings and highlights nothing.
    @Test func everySettingsLinkResolves() {
        let known = Set(SettingsSearchIndex.entries.map(\.anchor))
        for article in DroppyGuide.articles {
            for section in article.sections {
                for block in section.blocks {
                    guard case .settings(let links) = block else { continue }
                    for link in links {
                        #expect(known.contains(link.anchor),
                                "\(article.id): no Settings row for \(link.anchor)")
                    }
                }
            }
        }
    }

    /// A shortcut table that named an action twice would draw it twice.
    @Test func shortcutTablesDontRepeatThemselves() {
        for article in DroppyGuide.articles {
            for section in article.sections {
                for block in section.blocks {
                    guard case .shortcutTable(let actions) = block else { continue }
                    #expect(Set(actions).count == actions.count, "\(article.id) › \(section.title)")
                }
            }
        }
    }

    /// Every recordable shortcut is described somewhere, so the reference
    /// article doesn't quietly fall behind a new one.
    @Test func everyShortcutActionAppearsInTheReference() {
        guard let reference = DroppyGuide.article("shortcuts") else {
            Issue.record("The shortcuts article is missing")
            return
        }
        var listed: Set<ShortcutAction> = []
        for section in reference.sections {
            for block in section.blocks {
                if case .shortcutTable(let actions) = block { listed.formUnion(actions) }
            }
        }
        for action in ShortcutAction.allCases {
            #expect(listed.contains(action), "\(action.rawValue) is in no table")
        }
    }

    @Test func searchFindsAnArticleByItsOwnWords() {
        #expect(DroppyGuide.articles.contains { $0.matches("clipboard history") })
        #expect(DroppyGuide.articles.contains { $0.matches("shake basket") })
        // Every word has to match, so an unrelated pair finds nothing.
        #expect(!DroppyGuide.articles.contains { $0.matches("clipboard xyzzy") })
    }

    @Test func searchIgnoresCase() {
        let hits = DroppyGuide.articles.filter { $0.matches("AIRDROP") }
        #expect(!hits.isEmpty)
    }
}

/// Reading a crash report: the parts a person is shown, and what must not be
/// in what they paste.
@Suite struct CrashReportTests {

    /// A minimal `.ips`: a JSON header line, then the JSON body.
    private func writeReport(_ body: String, name: String = "Droppy-test.ips") throws -> URL {
        let header = #"{"app_name":"Droppy","app_version":"9.9.9","build_version":"42","os_version":"macOS 27.0 (26A428)","timestamp":"2026-09-20 13:23:14.00 +0700"}"#
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try (header + "\n" + body).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func readsTheHeadlineAndTheHeader() throws {
        let body = """
        {"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP","codes":"0x1, 0x2"},
         "termination":{"indicator":"Trace/BPT trap: 5"},
         "modelCode":"Mac15,7","cpuType":"ARM-64","uptime":12,
         "faultingThread":0,
         "threads":[{"frames":[{"imageIndex":0,"imageOffset":16,"symbol":"main","symbolLocation":4}]}],
         "usedImages":[{"name":"Droppy"}]}
        """
        let url = try writeReport(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = CrashReport(url: url, date: Date())
        #expect(report.headline == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(report.text.contains("9.9.9"))
        #expect(report.text.contains("macOS 27.0"))
        #expect(report.text.contains("Trace/BPT trap: 5"))
        #expect(report.text.contains("main"))
    }

    /// What gets pasted must not carry the home folder or the account name.
    @Test func sanitisesThePathsAndTheAccountName() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let body = """
        {"exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"},
         "termination":{"indicator":"\(home)/Library/Droppy"},
         "faultingThread":0,"threads":[],"usedImages":[]}
        """
        let url = try writeReport(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = CrashReport(url: url, date: Date())
        #expect(!report.text.contains(home))
        #expect(report.text.contains("~/Library/Droppy"))
    }

    /// A file that isn't the shape we expect still produces something to
    /// paste rather than an empty panel.
    @Test func fallsBackWhenTheFormatIsUnfamiliar() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-Droppy-broken.ips")
        try "not json at all\nand neither is this".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = CrashReport(url: url, date: Date())
        #expect(report.headline == "Crash report")
        #expect(report.text.contains("not json at all"))
    }

    /// An account named after something the report itself says — "Mac",
    /// "admin", "dev" — must not rewrite Tama's own headings.
    @Test func keepsTheHeadingsWhateverTheAccountIsCalled() throws {
        let body = """
        {"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
         "modelCode":"Mac15,7","cpuType":"ARM-64",
         "faultingThread":0,"threads":[],"usedImages":[]}
        """
        let url = try writeReport(body)
        defer { try? FileManager.default.removeItem(at: url) }
        let report = CrashReport(url: url, date: Date())
        #expect(report.text.contains("Mac: Mac15,7"))
        #expect(report.text.contains("macOS: macOS 27.0"))
        // The same, with the account actually called "Mac": the word on its
        // own goes, the model code and "macOS" stay whole.
        let cleaned = CrashReport.sanitise("Mac: Mac15,7 · macOS 27.0 · /Users/mac/x",
                                           home: "/Users/mac", accounts: ["Mac"])
        #expect(cleaned.contains("Mac15,7"))
        #expect(cleaned.contains("macOS 27.0"))
        #expect(cleaned.contains("~/x"))
        #expect(cleaned.hasPrefix("<user>:"))
    }

    @Test func aMissingFileDoesntThrow() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nothing-here.ips")
        let report = CrashReport(url: url, date: Date())
        #expect(report.headline == "Unreadable report")
    }
}


/// The Droplets store shows what a droplet will look like before it is turned
/// on. A droplet with no drawing of its own falls back to its icon and tag,
/// which is the "looks like nothing" the showcases exist to fix.
@Suite struct DropletShowcaseTests {

    @Test func everyDropletHasAConsoleDrawnForIt() {
        for droplet in AppState.defaultDroplets {
            #expect(ShowcaseCoverage.drawn.contains(droplet.id),
                    "\(droplet.id) has no showcase, so its store page shows only its icon")
        }
    }

    /// The other way round: a showcase for a droplet that no longer exists is
    /// dead drawing code.
    @Test func noShowcaseIsLeftBehind() {
        let ids = Set(AppState.defaultDroplets.map(\.id))
        for drawn in ShowcaseCoverage.drawn {
            #expect(ids.contains(drawn), "\(drawn) is drawn but is no longer a droplet")
        }
    }
}
