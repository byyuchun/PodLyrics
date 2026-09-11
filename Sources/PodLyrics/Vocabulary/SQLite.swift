import Foundation
import SQLite3

/// Minimal wrapper over the system SQLite3 C API: enough for the bundled
/// lexicon and the user store without pulling in a dependency.
final class SQLiteDB {
    struct Error: Swift.Error, CustomStringConvertible {
        let description: String
    }

    private let handle: OpaquePointer
    private let lock = NSLock()

    init(path: String, readOnly: Bool) throws {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            throw Error(description: "open \(path): \(message)")
        }
        handle = db
    }

    deinit { sqlite3_close(handle) }

    enum Value {
        case text(String)
        case int(Int)
        case double(Double)
        case null
    }

    struct Row {
        fileprivate let stmt: OpaquePointer
        func text(_ i: Int) -> String {
            guard let p = sqlite3_column_text(stmt, Int32(i)) else { return "" }
            return String(cString: p)
        }
        func int(_ i: Int) -> Int { Int(sqlite3_column_int64(stmt, Int32(i))) }
        func double(_ i: Int) -> Double { sqlite3_column_double(stmt, Int32(i)) }
        func isNull(_ i: Int) -> Bool { sqlite3_column_type(stmt, Int32(i)) == SQLITE_NULL }
    }

    func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw Error(description: String(cString: sqlite3_errmsg(handle)))
        }
    }

    func run(_ sql: String, _ params: [Value] = []) throws {
        _ = try query(sql, params) { _ in () }
    }

    func query<T>(_ sql: String, _ params: [Value] = [], _ map: (Row) -> T) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw Error(description: "prepare: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, transient)
            case .int(let n): sqlite3_bind_int64(stmt, idx, Int64(n))
            case .double(let d): sqlite3_bind_double(stmt, idx, d)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(map(Row(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw Error(description: "step: \(String(cString: sqlite3_errmsg(handle)))")
            }
        }
        return out
    }
}
