import AppKit
import Foundation
import SQLite3
import XCTest
@testable import DynamicIsland

// MARK: - Fixture database builder (tests only; writes temp files)

final class FixtureSQLite {
    let path: String
    private var db: OpaquePointer?

    init(directory: URL, name: String) throws {
        path = directory.appendingPathComponent(name).path
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw NSError(domain: "fixture", code: 1) }
    }

    deinit { sqlite3_close(db) }

    func exec(_ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            XCTFail("fixture SQL failed: \(String(cString: error!)) — \(sql)")
        }
    }

    func insert(_ sql: String, _ values: [Any?]) {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let v as Int64: sqlite3_bind_int64(statement, position, v)
            case let v as Int: sqlite3_bind_int64(statement, position, Int64(v))
            case let v as String: sqlite3_bind_text(statement, position, v, -1, transient)
            case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32(v.count), transient) }
            default: sqlite3_bind_null(statement, position)
            }
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement)
    }
}

private func notificationPayload(title: String?, body: String?, date: Date, nested: Bool) -> Data {
    var content: [String: Any] = [:]
    if let title { content["titl"] = title }
    if let body { content["body"] = body }
    var root: [String: Any] = ["app": "com.apple.MobileSMS", "date": date.timeIntervalSinceReferenceDate]
    if nested { root["req"] = content } else { root.merge(content) { $1 } }
    return try! PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
}

// MARK: - Notification Center

final class NotificationCenterIngestionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NCIngest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testParserHandlesFlatAndNestedRequestPayloads() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let flat = NotificationPayloadParser.parse(notificationPayload(title: "Alex", body: "Hi", date: date, nested: false))
        let nested = NotificationPayloadParser.parse(notificationPayload(title: "Alex", body: "Hi", date: date, nested: true))
        for parsed in [flat, nested] {
            XCTAssertEqual(parsed?.title, "Alex")
            XCTAssertEqual(parsed?.body, "Hi")
            XCTAssertEqual(parsed?.date, date)
            XCTAssertEqual(parsed?.bundleIdentifier, "com.apple.MobileSMS")
        }
        XCTAssertNil(NotificationPayloadParser.parse(Data("not a plist".utf8)))
    }

    func testDatabaseSourceReadsOnlyNewRecordsAfterBaseline() throws {
        let fixture = try FixtureSQLite(directory: directory, name: "db")
        fixture.exec("CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT)")
        fixture.exec("CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB, delivered_date REAL)")
        fixture.insert("INSERT INTO app VALUES (?, ?)", [1, "com.apple.MobileSMS"])
        fixture.insert("INSERT INTO record (rec_id, app_id, data) VALUES (?, ?, ?)", [10, 1, notificationPayload(title: "Old", body: "history", date: Date(), nested: true)])

        let source = NotificationCenterDatabaseSource(path: fixture.path)
        XCTAssertEqual(try source.latestRecordID(), 10)

        fixture.insert("INSERT INTO record (rec_id, app_id, data) VALUES (?, ?, ?)", [11, 1, notificationPayload(title: "Alex", body: "New one", date: Date(), nested: true)])
        let records = try source.records(after: 10, limit: 10)
        XCTAssertEqual(records.map(\.recordID), [11])
        XCTAssertEqual(records.first?.bundleIdentifier, "com.apple.MobileSMS")
        XCTAssertEqual(records.first?.body, "New one")
    }

    func testUnexpectedSchemaFailsClosed() throws {
        let fixture = try FixtureSQLite(directory: directory, name: "db")
        fixture.exec("CREATE TABLE record (id INTEGER PRIMARY KEY, payload BLOB)")
        fixture.exec("CREATE TABLE app (app_id INTEGER, identifier TEXT)")
        let source = NotificationCenterDatabaseSource(path: fixture.path)
        XCTAssertThrowsError(try source.latestRecordID()) {
            guard case ReadOnlySQLiteError.unsupportedSchema = $0 else { return XCTFail("\($0)") }
        }
    }

    @MainActor
    func testMonitorDeliversOnlyRecordsAfterStartAndReportsPermission() async throws {
        let fixture = try FixtureSQLite(directory: directory, name: "db")
        fixture.exec("CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT)")
        fixture.exec("CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB)")
        fixture.insert("INSERT INTO app VALUES (?, ?)", [1, "com.apple.MobileSMS"])
        fixture.insert("INSERT INTO record VALUES (?, ?, ?)", [1, 1, notificationPayload(title: "Old", body: "history", date: Date(), nested: false)])

        let monitor = SystemNotificationMonitor(
            makeSource: { NotificationCenterDatabaseSource(path: fixture.path) },
            fullDiskAccess: { .granted }
        )
        var delivered: [SystemNotificationRecord] = []
        monitor.onRecord = { delivered.append($0) }
        monitor.start()
        XCTAssertEqual(monitor.state, .running)

        fixture.insert("INSERT INTO record VALUES (?, ?, ?)", [2, 1, notificationPayload(title: "Alex", body: "fresh", date: Date(), nested: false)])
        monitor.fetch()
        for _ in 0..<100 where delivered.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(delivered.map(\.recordID), [2], "History is never replayed")
        monitor.stop()

        let denied = SystemNotificationMonitor(makeSource: { XCTFail("must not open without FDA"); return nil }, fullDiskAccess: { .denied })
        denied.start()
        XCTAssertEqual(denied.state, .permissionRequired)
    }
}

// MARK: - Messages database + resolver

final class MessagesConversationResolverTests: XCTestCase {
    private var directory: URL!
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MsgResolve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDatabase() throws -> FixtureSQLite {
        let db = try FixtureSQLite(directory: directory, name: "chat.db")
        db.exec("CREATE TABLE message (ROWID INTEGER PRIMARY KEY, text TEXT, attributedBody BLOB, date INTEGER, is_from_me INTEGER)")
        db.exec("CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, guid TEXT, service_name TEXT, style INTEGER)")
        db.exec("CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER)")
        db.insert("INSERT INTO chat VALUES (?, ?, ?, ?)", [1, "iMessage;-;+15550001", "iMessage", 45])
        db.insert("INSERT INTO chat VALUES (?, ?, ?, ?)", [2, "iMessage;+;chat999", "iMessage", 43])
        return db
    }

    private func addMessage(_ db: FixtureSQLite, id: Int, chat: Int, text: String?, attributed: Data? = nil, at date: Date, fromMe: Bool = false) {
        db.insert("INSERT INTO message VALUES (?, ?, ?, ?, ?)", [id, text, attributed, Int64(date.timeIntervalSinceReferenceDate * 1e9), fromMe ? 1 : 0])
        db.insert("INSERT INTO chat_message_join VALUES (?, ?)", [chat, id])
    }

    func testStoreReadsWindowedMessagesWithNanosecondDates() throws {
        let db = try makeDatabase()
        addMessage(db, id: 1, chat: 1, text: "Nachos at seven?", at: base)
        addMessage(db, id: 2, chat: 2, text: "old", at: base.addingTimeInterval(-3_600))
        let store = MessagesDatabaseStore(path: db.path)

        let rows = try store.messages(from: base.addingTimeInterval(-60), to: base.addingTimeInterval(60), limit: 50)
        XCTAssertEqual(rows.map(\.rowID), [1])
        XCTAssertEqual(rows.first?.chatGUID, "iMessage;-;+15550001")
        XCTAssertEqual(rows.first?.date.timeIntervalSinceReferenceDate ?? 0, base.timeIntervalSinceReferenceDate, accuracy: 0.001)
        XCTAssertFalse(rows.first?.isGroup ?? true)
    }

    func testStoreDecodesAttributedBodyWhenTextIsNull() throws {
        let db = try makeDatabase()
        let archived = NSArchiver.archivedData(withRootObject: NSAttributedString(string: "only in attributed body"))
        addMessage(db, id: 1, chat: 1, text: nil, attributed: archived, at: base)
        let rows = try MessagesDatabaseStore(path: db.path).messages(from: base.addingTimeInterval(-5), to: base.addingTimeInterval(5), limit: 5)
        XCTAssertEqual(rows.first?.text, "only in attributed body")
    }

    func testOutgoingMessagesAreScopedToExactChat() throws {
        let db = try makeDatabase()
        addMessage(db, id: 1, chat: 1, text: "reply", at: base, fromMe: true)
        addMessage(db, id: 2, chat: 2, text: "reply", at: base, fromMe: true)
        let rows = try MessagesDatabaseStore(path: db.path).outgoingMessages(inChat: "iMessage;-;+15550001", since: base.addingTimeInterval(-1))
        XCTAssertEqual(rows.map(\.rowID), [1])
    }

    func testStoreRejectsUnexpectedSchema() throws {
        let db = try FixtureSQLite(directory: directory, name: "bad.db")
        db.exec("CREATE TABLE message (id INTEGER, body TEXT)")
        XCTAssertThrowsError(try MessagesDatabaseStore(path: db.path).messages(from: base, to: base, limit: 1))
    }

    func testResolverRequiresExactlyOneMatchingChat() {
        let notification = record(body: "Nachos at seven?")
        let exact = MessagesConversationResolver.resolve(notification: notification, candidates: [
            message(1, chat: "A", text: "Nachos at seven?", at: base),
            message(2, chat: "B", text: "Something else", at: base)
        ])
        XCTAssertEqual(exact, .exact(chatGUID: "A", isGroup: false, service: "iMessage"))

        let ambiguous = MessagesConversationResolver.resolve(notification: notification, candidates: [
            message(1, chat: "A", text: "Nachos at seven?", at: base),
            message(2, chat: "B", text: "Nachos at seven?", at: base)
        ])
        XCTAssertEqual(ambiguous, .ambiguous(candidateChats: 2))
    }

    func testResolverFailsClosedWithoutEvidence() {
        let candidates = [message(1, chat: "A", text: "hello", at: base)]
        XCTAssertEqual(MessagesConversationResolver.resolve(notification: record(body: nil), candidates: candidates), .notFound)
        XCTAssertEqual(MessagesConversationResolver.resolve(notification: record(body: "different"), candidates: candidates), .notFound)
        XCTAssertEqual(
            MessagesConversationResolver.resolve(notification: record(body: "hello"), candidates: [message(1, chat: "A", text: "hello", at: base.addingTimeInterval(-600))]),
            .notFound,
            "Outside the time window"
        )
        XCTAssertEqual(
            MessagesConversationResolver.resolve(notification: record(body: "hello"), candidates: [message(1, chat: "A", text: "hello", at: base, fromMe: true)]),
            .notFound,
            "Own messages are never evidence"
        )
    }

    func testResolverAcceptsTruncatedNotificationBodyOnlyWithEnoughPrefix() {
        let long = "This is a fairly long message that the notification truncated at some point"
        XCTAssertEqual(
            MessagesConversationResolver.resolve(notification: record(body: "This is a fairly long message…"), candidates: [message(1, chat: "A", text: long, at: base)]),
            .exact(chatGUID: "A", isGroup: false, service: "iMessage")
        )
        XCTAssertEqual(
            MessagesConversationResolver.resolve(notification: record(body: "Hi…"), candidates: [message(1, chat: "A", text: "Hi there", at: base)]),
            .notFound
        )
    }

    private func record(body: String?) -> SystemNotificationRecord {
        SystemNotificationRecord(recordID: 1, bundleIdentifier: "com.apple.MobileSMS", title: "Alex", subtitle: nil, body: body, deliveredAt: base)
    }

    private func message(_ id: Int64, chat: String, text: String?, at date: Date, fromMe: Bool = false) -> MessagesDatabaseMessage {
        MessagesDatabaseMessage(rowID: id, chatGUID: chat, isGroup: false, service: "iMessage", text: text, date: date, isFromMe: fromMe)
    }
}

