// 很小的 SQLite 帮手：读写 Anki 卡组里的数据库（.apkg 里装的就是一个 SQLite 文件）。
import Foundation
import SQLite3

enum SQLValue: Equatable {
    case int(Int64), double(Double), text(String), blob(Data), null

    var int: Int64? { if case .int(let v) = self { v } else if case .double(let d) = self { Int64(d) } else { nil } }
    var string: String? {
        switch self {
        case .text(let s): s
        case .int(let v): String(v)
        case .blob(let d): String(data: d, encoding: .utf8)
        default: nil
        }
    }
    var data: Data? {
        switch self {
        case .blob(let d): d
        case .text(let s): Data(s.utf8)
        default: nil
        }
    }
}

struct SQLiteError: LocalizedError {
    let message: String
    var errorDescription: String? { "SQLite: \(message)" }
}

final class SQLiteDB {
    nonisolated(unsafe) private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw SQLiteError(message: message)
        }
    }

    deinit { sqlite3_close(db) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw SQLiteError(message: message)
        }
    }

    @discardableResult
    func query(_ sql: String, _ args: [SQLValue] = []) throws -> [[SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError }
        defer { sqlite3_finalize(statement) }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case .int(let v): sqlite3_bind_int64(statement, index, v)
            case .double(let v): sqlite3_bind_double(statement, index, v)
            case .text(let s): sqlite3_bind_text(statement, index, s, -1, Self.transient)
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(d.count), Self.transient) }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        var rows: [[SQLValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw lastError }
            rows.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
        }
        return rows
    }

    func tableExists(_ name: String) -> Bool {
        ((try? query("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [.text(name)])) ?? []).isEmpty == false
    }

    private func column(_ statement: OpaquePointer?, _ i: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, i) {
        case SQLITE_INTEGER: return .int(sqlite3_column_int64(statement, i))
        case SQLITE_FLOAT: return .double(sqlite3_column_double(statement, i))
        case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, i)))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, i))
            guard count > 0, let pointer = sqlite3_column_blob(statement, i) else { return .blob(Data()) }
            return .blob(Data(bytes: pointer, count: count))
        default: return .null
        }
    }

    private var lastError: SQLiteError {
        SQLiteError(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
    }
}
