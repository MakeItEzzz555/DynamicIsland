import Foundation

/// One Messages database row, reduced to what correlation needs. Text is
/// used only for in-memory matching and is never logged or persisted.
struct MessagesDatabaseMessage: Equatable, Sendable {
    let rowID: Int64
    let chatGUID: String
    let isGroup: Bool
    let service: String?
    let text: String?
    let date: Date
    let isFromMe: Bool
}

protocol MessagesConversationStore: AnyObject, Sendable {
    /// Messages in the bounded window, joined to their chat.
    func messages(from start: Date, to end: Date, limit: Int) throws -> [MessagesDatabaseMessage]
    /// Outgoing messages recorded in one exact chat since `date`.
    func outgoingMessages(inChat chatGUID: String, since date: Date) throws -> [MessagesDatabaseMessage]
}

/// Read-only Messages database access with runtime schema validation.
final class MessagesDatabaseStore: MessagesConversationStore, @unchecked Sendable {
    static let requiredSchema: [String: Set<String>] = [
        "message": ["ROWID", "text", "date", "is_from_me"],
        "chat": ["ROWID", "guid"],
        "chat_message_join": ["chat_id", "message_id"]
    ]

    let path: String

    init(path: String = MessagesDatabaseLocation.candidates[0]) {
        self.path = path
    }

    private func open() throws -> (ReadOnlySQLiteDatabase, hasAttributedBody: Bool, chatColumns: Set<String>) {
        let database = try ReadOnlySQLiteDatabase(path: path)
        try database.require(Self.requiredSchema)
        let messageColumns = try database.columns(of: "message")
        let chatColumns = try database.columns(of: "chat")
        return (database, messageColumns.contains("attributedBody"), chatColumns)
    }

    func messages(from start: Date, to end: Date, limit: Int) throws -> [MessagesDatabaseMessage] {
        let (database, hasAttributedBody, chatColumns) = try open()
        let (low, high, nanoseconds) = try Self.dateBounds(database, start: start, end: end)
        let sql = """
            SELECT m.ROWID AS rowid, m.text AS text, \(hasAttributedBody ? "m.attributedBody" : "NULL") AS attributed,
                   m.date AS date, m.is_from_me AS from_me, c.guid AS guid,
                   \(chatColumns.contains("service_name") ? "c.service_name" : "NULL") AS service,
                   \(chatColumns.contains("style") ? "c.style" : "NULL") AS style
            FROM message m
            JOIN chat_message_join j ON j.message_id = m.ROWID
            JOIN chat c ON c.ROWID = j.chat_id
            WHERE m.date BETWEEN ? AND ?
            ORDER BY m.date DESC LIMIT ?
            """
        return try database.rows(sql, [low, high, .integer(Int64(limit))]).compactMap {
            Self.message(from: $0, nanoseconds: nanoseconds)
        }
    }

    func outgoingMessages(inChat chatGUID: String, since date: Date) throws -> [MessagesDatabaseMessage] {
        let (database, hasAttributedBody, chatColumns) = try open()
        let (low, _, nanoseconds) = try Self.dateBounds(database, start: date, end: date)
        let sql = """
            SELECT m.ROWID AS rowid, m.text AS text, \(hasAttributedBody ? "m.attributedBody" : "NULL") AS attributed,
                   m.date AS date, m.is_from_me AS from_me, c.guid AS guid,
                   \(chatColumns.contains("service_name") ? "c.service_name" : "NULL") AS service,
                   \(chatColumns.contains("style") ? "c.style" : "NULL") AS style
            FROM message m
            JOIN chat_message_join j ON j.message_id = m.ROWID
            JOIN chat c ON c.ROWID = j.chat_id
            WHERE c.guid = ? AND m.is_from_me = 1 AND m.date >= ?
            ORDER BY m.date DESC LIMIT 20
            """
        return try database.rows(sql, [.text(chatGUID), low]).compactMap {
            Self.message(from: $0, nanoseconds: nanoseconds)
        }
    }

    /// Messages stores dates as seconds or nanoseconds since 2001; detect
    /// the unit from the live data instead of assuming it.
    private static func dateBounds(
        _ database: ReadOnlySQLiteDatabase,
        start: Date,
        end: Date
    ) throws -> (ReadOnlySQLiteDatabase.Value, ReadOnlySQLiteDatabase.Value, Bool) {
        let sample = try database.rows("SELECT MAX(date) AS d FROM message").first?["d"]?.double ?? 0
        let nanoseconds = sample > 1e12
        let scale = nanoseconds ? 1e9 : 1
        return (
            .integer(Int64(start.timeIntervalSinceReferenceDate * scale)),
            .integer(Int64(end.timeIntervalSinceReferenceDate * scale)),
            nanoseconds
        )
    }

    private static func message(from row: ReadOnlySQLiteDatabase.Row, nanoseconds: Bool) -> MessagesDatabaseMessage? {
        guard let rowID = row["rowid"]?.int64,
              let guid = row["guid"]?.string,
              let raw = row["date"]?.double else { return nil }
        let text = row["text"]?.string ?? row["attributed"]?.data.flatMap(MessagesAttributedBodyDecoder.text(from:))
        return MessagesDatabaseMessage(
            rowID: rowID,
            chatGUID: guid,
            isGroup: (row["style"]?.int64 ?? 0) == 43,
            service: row["service"]?.string,
            text: text,
            date: Date(timeIntervalSinceReferenceDate: nanoseconds ? raw / 1e9 : raw),
            isFromMe: (row["from_me"]?.int64 ?? 0) == 1
        )
    }
}

/// Newer Messages rows may keep text only in `attributedBody`, an archived
/// NSAttributedString (typedstream). Decoded in memory for matching only.
enum MessagesAttributedBodyDecoder {
    static func text(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard let object = try? NSUnarchiver.unarchiveObject(with: data) else { return nil }
        if let attributed = object as? NSAttributedString { return attributed.string }
        return object as? String
    }
}

enum MessagesResolution: Equatable, Sendable {
    case exact(chatGUID: String, isGroup: Bool, service: String?)
    case ambiguous(candidateChats: Int)
    case notFound
}

/// Maps one Messages notification to exactly one chat, or nothing.
/// Evidence: incoming direction, a bounded time window around delivery, and
/// a body match. Display names are never used for targeting.
enum MessagesConversationResolver {
    static let windowBefore: TimeInterval = 120
    static let windowAfter: TimeInterval = 15

    static func resolve(
        notification: SystemNotificationRecord,
        candidates: [MessagesDatabaseMessage]
    ) -> MessagesResolution {
        guard let body = normalize(notification.body), !body.isEmpty else { return .notFound }
        let low = notification.deliveredAt.addingTimeInterval(-windowBefore)
        let high = notification.deliveredAt.addingTimeInterval(windowAfter)
        let matches = candidates.filter { candidate in
            guard !candidate.isFromMe,
                  candidate.date >= low, candidate.date <= high,
                  let text = normalize(candidate.text) else { return false }
            return textMatches(notificationBody: body, messageText: text)
        }
        let chats = Dictionary(grouping: matches, by: \.chatGUID)
        switch chats.count {
        case 0:
            return .notFound
        case 1:
            let message = matches.max { $0.date < $1.date }!
            return .exact(chatGUID: message.chatGUID, isGroup: message.isGroup, service: message.service)
        default:
            return .ambiguous(candidateChats: chats.count)
        }
    }

    /// Notification bodies can be truncated with an ellipsis.
    static func textMatches(notificationBody: String, messageText: String) -> Bool {
        if notificationBody == messageText { return true }
        for ellipsis in ["…", "..."] where notificationBody.hasSuffix(ellipsis) {
            let prefix = String(notificationBody.dropLast(ellipsis.count)).trimmingCharacters(in: .whitespaces)
            if prefix.count >= 8, messageText.hasPrefix(prefix) { return true }
        }
        return false
    }

    static func normalize(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
