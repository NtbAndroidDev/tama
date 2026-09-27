import Foundation
import SQLite3

/// A read-only SQLite connection for databases other apps own (the macOS
/// notification store, Messages' chat.db, Cursor's state.vscdb). It never
/// writes; each query runs in its own read transaction, so it sees the
/// owner's latest commits (WAL included). Not thread-safe: use one queue.
final class SQLiteReader {
    enum Value: Equatable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)

        var int: Int64? {
            switch self {
            case let .integer(v): v
            case let .real(v): Int64(v)
            case let .text(v): Int64(v)
            default: nil
            }
        }
        var double: Double? {
            switch self {
            case let .integer(v): Double(v)
            case let .real(v): v
            case let .text(v): Double(v)
            default: nil
            }
        }
        var string: String? {
            switch self {
            case let .text(v): v
            case let .integer(v): String(v)
            case let .blob(v): String(data: v, encoding: .utf8)
            default: nil
            }
        }
        var data: Data? {
            switch self {
            case let .blob(v): v
            case let .text(v): Data(v.utf8)
            default: nil
            }
        }
    }

    enum OpenError: Error, Equatable {
        /// macOS privacy (Full Disk Access) or file permissions said no.
        case notPermitted
        case missing
        case failed(String)
    }

    private var db: OpaquePointer?

    init(path: String) throws {
        // Probe with open(2) first: SQLite reports a TCC refusal as a vague
        // "unable to open", while errno says EPERM.
        let fd = open(path, O_RDONLY)
        if fd < 0 {
            switch errno {
            case EPERM, EACCES: throw OpenError.notPermitted
            case ENOENT: throw OpenError.missing
            default: throw OpenError.failed(String(cString: strerror(errno)))
            }
        }
        close(fd)
        var components = URLComponents()
        components.scheme = "file"
        components.path = path
        components.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        let uri = components.string ?? "file:\(path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw OpenError.failed(message)
        }
        sqlite3_busy_timeout(db, 250)
    }

    deinit { sqlite3_close(db) }

    /// Rows for `sql` with `?` parameters bound in order.
    func query(_ sql: String, _ parameters: [Value] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw OpenError.failed(db.map { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch parameter {
            case .null: sqlite3_bind_null(statement, index)
            case let .integer(v): sqlite3_bind_int64(statement, index, v)
            case let .real(v): sqlite3_bind_double(statement, index, v)
            case let .text(v): sqlite3_bind_text(statement, index, v, -1, transient)
            case let .blob(v):
                _ = v.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(v.count), transient) }
            }
        }
        var rows: [[Value]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw OpenError.failed(db.map { String(cString: sqlite3_errmsg($0)) } ?? "step failed")
            }
            let count = sqlite3_column_count(statement)
            var row: [Value] = []
            row.reserveCapacity(Int(count))
            for column in 0..<count {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, column) {
                        row.append(.text(String(cString: text)))
                    } else {
                        row.append(.null)
                    }
                case SQLITE_BLOB:
                    let length = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column), length > 0 {
                        row.append(.blob(Data(bytes: bytes, count: length)))
                    } else {
                        row.append(.blob(Data()))
                    }
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Column names of a table ("PRAGMA table_info").
    func columns(of table: String) -> Set<String> {
        let rows = (try? query("PRAGMA table_info(\(table))")) ?? []
        return Set(rows.compactMap { $0.count > 1 ? $0[1].string : nil })
    }
}
