import Foundation
import SQLite3

enum ReadOnlySQLiteError: Error, Equatable {
    /// Missing file, or macOS refused access (Full Disk Access not granted).
    case cannotOpen(code: Int32)
    case notPermitted
    case query(String)
    case unsupportedSchema(String)
}

/// Minimal read-only SQLite access for system databases (Notification
/// Center, Messages). Always opened with SQLITE_OPEN_READONLY; never writes.
final class ReadOnlySQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard FileManager.default.isReadableFile(atPath: path) || FileManager.default.fileExists(atPath: path) else {
            if Self.isPermissionDenied(path: path) { throw ReadOnlySQLiteError.notPermitted }
            throw ReadOnlySQLiteError.cannotOpen(code: SQLITE_CANTOPEN)
        }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            sqlite3_close(db)
            if Self.isPermissionDenied(path: path) { throw ReadOnlySQLiteError.notPermitted }
            throw ReadOnlySQLiteError.cannotOpen(code: code)
        }
        sqlite3_busy_timeout(db, 250)
        handle = db
        // Opening can succeed lazily; the first read reveals EPERM.
        do {
            _ = try rows("SELECT name FROM sqlite_master LIMIT 1")
        } catch {
            close()
            if Self.isPermissionDenied(path: path) { throw ReadOnlySQLiteError.notPermitted }
            throw error
        }
    }

    deinit { close() }

    func close() {
        if let handle { sqlite3_close(handle) }
        handle = nil
    }

    enum Value: Equatable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)

        var int64: Int64? {
            switch self {
            case .integer(let value): value
            case .real(let value): Int64(value)
            case .text(let value): Int64(value)
            default: nil
            }
        }

        var double: Double? {
            switch self {
            case .integer(let value): Double(value)
            case .real(let value): value
            case .text(let value): Double(value)
            default: nil
            }
        }

        var string: String? {
            if case .text(let value) = self { return value }
            return nil
        }

        var data: Data? {
            switch self {
            case .blob(let value): value
            case .text(let value): Data(value.utf8)
            default: nil
            }
        }
    }

    typealias Row = [String: Value]

    /// Parameterized query. Bindings are positional (`?`).
    func rows(_ sql: String, _ bindings: [Value] = []) throws -> [Row] {
        guard let handle else { throw ReadOnlySQLiteError.query("closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadOnlySQLiteError.query(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .null: sqlite3_bind_null(statement, position)
            case .integer(let v): sqlite3_bind_int64(statement, position, v)
            case .real(let v): sqlite3_bind_double(statement, position, v)
            case .text(let v): sqlite3_bind_text(statement, position, v, -1, Self.transient)
            case .blob(let v):
                _ = v.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32(v.count), Self.transient) }
            }
        }
        var result: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw ReadOnlySQLiteError.query(String(cString: sqlite3_errmsg(handle)))
            }
            var row: Row = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row[name] = .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column), count > 0 {
                        row[name] = .blob(Data(bytes: bytes, count: count))
                    } else {
                        row[name] = .blob(Data())
                    }
                default: row[name] = .null
                }
            }
            result.append(row)
        }
        return result
    }

    /// Column names per table, read from the live schema.
    func columns(of table: String) throws -> Set<String> {
        let safe = table.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return Set(try rows("PRAGMA table_info(\(safe))").compactMap { $0["name"]?.string })
    }

    /// Throws `.unsupportedSchema` unless every required column exists.
    func require(_ requirements: [String: Set<String>]) throws {
        for (table, required) in requirements {
            let present = try columns(of: table)
            let missing = required.subtracting(present)
            guard missing.isEmpty else {
                throw ReadOnlySQLiteError.unsupportedSchema("\(table) is missing \(missing.sorted().joined(separator: ", "))")
            }
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func isPermissionDenied(path: String) -> Bool {
        let descriptor = open(path, O_RDONLY)
        if descriptor >= 0 {
            Darwin.close(descriptor)
            return false
        }
        return errno == EPERM || errno == EACCES
    }
}

// MARK: - Full Disk Access

enum FullDiskAccessState: Equatable, Sendable {
    case granted
    case denied
    /// The probe files do not exist on this macOS version.
    case unknown
}

/// Detects Full Disk Access truthfully by attempting a read-only open of
/// protected files. Never prompts; macOS has no request API for FDA.
enum FullDiskAccessProbe {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func state(probePaths: [String] = MessagesDatabaseLocation.candidates + NotificationCenterDatabaseLocation.candidates) -> FullDiskAccessState {
        var sawExisting = false
        for path in probePaths {
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return .granted
            }
            if errno == EPERM || errno == EACCES {
                sawExisting = true
            }
        }
        return sawExisting ? .denied : .unknown
    }
}

enum MessagesDatabaseLocation {
    static var candidates: [String] {
        [(NSHomeDirectory() as NSString).appendingPathComponent("Library/Messages/chat.db")]
    }
}

enum NotificationCenterDatabaseLocation {
    /// Known locations: macOS 15+ group container, and the older per-user
    /// Darwin directory location.
    static var candidates: [String] {
        var paths = [(NSHomeDirectory() as NSString).appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")]
        if let darwin = darwinUserDirectory() {
            paths.append((darwin as NSString).appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }
        return paths
    }

    private static func darwinUserDirectory() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count)
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
