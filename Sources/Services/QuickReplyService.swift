import AppKit

/// Quick reply from the Notification HUD.
///
/// - Messages: the reply goes out through Messages' AppleScript, to the chat
///   the notification came from. The chat is found in Messages' own database
///   (chat.db, readable with the same Full Disk Access the HUD needs) by
///   matching the incoming message; failing that, from the notification's
///   thread identifier.
/// - WhatsApp and Telegram have no scripting interface, so a reply can't be
///   sent for you: the chat app opens with your reply on the clipboard.
@MainActor
enum QuickReplyService {
    enum Outcome: Equatable {
        case sent
        case copiedAndOpened(String)
        case failed(String)
    }

    static func reply(_ text: String, to notification: MirroredNotification) async -> Outcome {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return .failed("Type a message, then press Return to send.") }
        switch notification.replyKind {
        case .messages:
            return await replyInMessages(message, to: notification)
        case .whatsapp:
            return openChatApp(["net.whatsapp.WhatsApp", "desktop.WhatsApp"], web: "https://web.whatsapp.com",
                               name: "WhatsApp", copying: message)
        case .telegram:
            return openChatApp(["ru.keepcoder.Telegram", "org.telegram.desktop"], web: "https://web.telegram.org",
                               name: "Telegram", copying: message)
        case .none:
            return .failed("\(NotificationHUDService.appName(for: notification.bundleID)) doesn't support quick reply.")
        }
    }

    // MARK: Messages

    private static func replyInMessages(_ text: String, to notification: MirroredNotification) async -> Outcome {
        let body = notification.body
        let delivered = notification.date
        let thread = notification.threadID
        let target = await Task.detached(priority: .userInitiated) {
            resolveMessagesTarget(body: body, delivered: delivered, threadID: thread)
        }.value
        guard let target else {
            return .failed("Couldn't tell who sent this message. Reply in Messages instead.")
        }
        let result = await Task.detached(priority: .userInitiated) { sendInMessages(text, target: target) }.value
        if let error = result { return .failed(error) }
        return .sent
    }

    enum MessagesTarget: Equatable, Sendable {
        /// A chat's GUID ("iMessage;-;+15551234567", "any;+;chat1234…").
        case chat(String)
        /// A phone number or email address.
        case handle(String)
    }

    /// The chat to answer: the newest incoming message with this text in
    /// chat.db, else the most recent incoming message around the time the
    /// notification arrived, else whatever the thread identifier names.
    nonisolated static func resolveMessagesTarget(body: String, delivered: Date, threadID: String?) -> MessagesTarget? {
        let path = NSHomeDirectory() + "/Library/Messages/chat.db"
        if let reader = try? SQLiteReader(path: path) {
            let select = """
                SELECT c.guid, h.id FROM message m
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                LEFT JOIN chat_message_join j ON j.message_id = m.ROWID
                LEFT JOIN chat c ON c.ROWID = j.chat_id
                """
            var rows = (try? reader.query(select + " WHERE m.is_from_me = 0 AND m.text = ? ORDER BY m.date DESC LIMIT 1",
                                          [.text(body)])) ?? []
            if rows.isEmpty {
                // Newer messages keep their text only in attributedBody; fall back
                // to time: message.date is nanoseconds since 2001.
                let around = Int64(delivered.timeIntervalSinceReferenceDate * 1_000_000_000)
                let window: Int64 = 120 * 1_000_000_000
                rows = (try? reader.query(select + " WHERE m.is_from_me = 0 AND m.date BETWEEN ? AND ? ORDER BY m.date DESC LIMIT 1",
                                          [.integer(around - window), .integer(around + window)])) ?? []
            }
            if let row = rows.first {
                if let guid = row.first?.string, !guid.isEmpty { return .chat(guid) }
                if row.count > 1, let handle = row[1].string, !handle.isEmpty { return .handle(handle) }
            }
        }
        return target(fromThread: threadID)
    }

    /// "iMessage;-;+15551234567" is a chat GUID; a bare number or address is a handle.
    nonisolated static func target(fromThread thread: String?) -> MessagesTarget? {
        guard let thread = thread?.trimmingCharacters(in: .whitespaces), !thread.isEmpty else { return nil }
        if thread.contains(";-;") || thread.contains(";+;") { return .chat(thread) }
        if thread.contains("@") || thread.allSatisfy({ $0.isNumber || "+-() ".contains($0) }) {
            return .handle(thread)
        }
        return nil
    }

    /// Sends through Messages; nil on success, else what went wrong.
    nonisolated private static func sendInMessages(_ text: String, target: MessagesTarget) -> String? {
        let script: String
        let argument: String
        switch target {
        case let .chat(guid):
            argument = guid
            script = """
            on run argv
                tell application "Messages" to send (item 1 of argv) to chat id (item 2 of argv)
            end run
            """
        case let .handle(handle):
            argument = handle
            script = """
            on run argv
                tell application "Messages"
                    set targetService to 1st account whose service type = iMessage
                    send (item 1 of argv) to participant (item 2 of argv) of targetService
                end tell
            end run
            """
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, text, argument]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not allowed") {
            return "Allow Tama to control Messages in System Settings › Privacy & Security › Automation."
        }
        return message.isEmpty ? "Messages couldn't send the reply." : message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: WhatsApp / Telegram

    private static func openChatApp(_ bundleIDs: [String], web: String, name: String, copying text: String) -> Outcome {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if let url = bundleIDs.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: web) {
            NSWorkspace.shared.open(url)
        }
        return .copiedAndOpened("\(name) doesn't let other apps send messages, so your reply is on the clipboard — paste it in the chat.")
    }
}
