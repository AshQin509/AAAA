import Foundation
import SQLite3

public struct ErrorRecord: Identifiable, Sendable {
    public let id: String
    public let diagnostic: Diagnostic
    public let occurrences: Int
    public let active: Bool
}
public struct TopicStat: Codable, Sendable {
    public let topic: String
    public let occurrences: Int
    public let answered: Int
    public let correct: Int
    public init(topic: String, occurrences: Int, answered: Int, correct: Int) { self.topic = topic; self.occurrences = occurrences; self.answered = answered; self.correct = correct }
}
public final class ErrorStore {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public init(url: URL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { if db != nil { sqlite3_close(db) }; throw CoachError.message("Could not open the learning database.") }
        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("CREATE TABLE IF NOT EXISTS errors(project TEXT, fingerprint TEXT, payload TEXT NOT NULL, category TEXT NOT NULL, occurrences INTEGER NOT NULL, active INTEGER NOT NULL, first_seen REAL, last_seen REAL, PRIMARY KEY(project,fingerprint)); CREATE TABLE IF NOT EXISTS attempts(id TEXT PRIMARY KEY, project TEXT NOT NULL, topic TEXT NOT NULL, correct INTEGER NOT NULL, created REAL);")
            // Preserve learning history from earlier Chinese-language builds.
            try execute("BEGIN IMMEDIATE;")
            do {
                try run("UPDATE errors SET category=? WHERE category=?", ["Symbols and scope","\u{7b26}\u{53f7}\u{4e0e}\u{4f5c}\u{7528}\u{57df}"])
                try run("UPDATE attempts SET topic=? WHERE topic=?", ["Symbols and scope","\u{7b26}\u{53f7}\u{4e0e}\u{4f5c}\u{7528}\u{57df}"])
                try run("UPDATE errors SET category=? WHERE category=?", ["Types and conversions","\u{7c7b}\u{578b}\u{4e0e}\u{8f6c}\u{6362}"])
                try run("UPDATE attempts SET topic=? WHERE topic=?", ["Types and conversions","\u{7c7b}\u{578b}\u{4e0e}\u{8f6c}\u{6362}"])
                try run("UPDATE errors SET category=? WHERE category=?", ["Methods and arguments","\u{65b9}\u{6cd5}\u{4e0e}\u{53c2}\u{6570}"])
                try run("UPDATE attempts SET topic=? WHERE topic=?", ["Methods and arguments","\u{65b9}\u{6cd5}\u{4e0e}\u{53c2}\u{6570}"])
                try run("UPDATE errors SET category=? WHERE category=?", ["Static and instance members","static \u{4e0e}\u{5b9e}\u{4f8b}"])
                try run("UPDATE attempts SET topic=? WHERE topic=?", ["Static and instance members","static \u{4e0e}\u{5b9e}\u{4f8b}"])
                try run("UPDATE errors SET category=? WHERE category=?", ["Syntax and structure","\u{8bed}\u{6cd5}\u{4e0e}\u{7ed3}\u{6784}"])
                try run("UPDATE attempts SET topic=? WHERE topic=?", ["Syntax and structure","\u{8bed}\u{6cd5}\u{4e0e}\u{7ed3}\u{6784}"])
                try run("UPDATE errors SET category=? WHERE category=?", ["Java fundamentals","Java \u{7f16}\u{8bd1}\u{57fa}\u{7840}"])
                try run("UPDATE attempts SET topic=? WHERE topic=?", ["Java fundamentals","Java \u{7f16}\u{8bd1}\u{57fa}\u{7840}"])
                try execute("COMMIT;")
            } catch { try? execute("ROLLBACK;"); throw error }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CoachError.message("Could not write learning records.") } }
    private func statement(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw CoachError.message("Could not read learning records.") }
        for (i,v) in values.enumerated() { sqlite3_bind_text(s, Int32(i+1), v, -1, transient) }
        return s
    }
    private func run(_ sql: String, _ values: [String]) throws {
        let s = try statement(sql, values); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw CoachError.message("Could not save learning records.") }
    }
    // A persistent error is counted once, then again only after it disappears and returns.
    public func reconcile(project: String, diagnostics: [Diagnostic]) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let previous = Set(try records(project: project).filter(\.active).map(\.id))
            try run("UPDATE errors SET active=0 WHERE project=?", [project])
            for d in Dictionary(diagnostics.map { ($0.id, $0) }, uniquingKeysWith: { a,_ in a }).values {
                let payload = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
                let increment = previous.contains(d.id) ? "0" : "1"
                try run("INSERT INTO errors VALUES(?,?,?,?,1,1,?,?) ON CONFLICT(project,fingerprint) DO UPDATE SET active=1,last_seen=excluded.last_seen,payload=excluded.payload,occurrences=errors.occurrences+" + increment, [project,d.id,payload,d.category,String(Date().timeIntervalSince1970),String(Date().timeIntervalSince1970)])
            }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }
    public func records(project: String) throws -> [ErrorRecord] {
        let s = try statement("SELECT fingerprint,payload,occurrences,active FROM errors WHERE project=? ORDER BY last_seen DESC LIMIT 500", [project]); defer { sqlite3_finalize(s) }
        var result: [ErrorRecord] = []
        while sqlite3_step(s) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(s,0)); let payload = String(cString: sqlite3_column_text(s,1))
            let d = try JSONDecoder().decode(Diagnostic.self, from: Data(payload.utf8))
            result.append(ErrorRecord(id: id, diagnostic: d, occurrences: Int(sqlite3_column_int(s,2)), active: sqlite3_column_int(s,3) == 1))
        }
        return result
    }
    public func stats(project: String) throws -> [TopicStat] {
        let s = try statement("SELECT category,SUM(occurrences),(SELECT COUNT(*) FROM attempts WHERE project=? AND topic=category),(SELECT COUNT(*) FROM attempts WHERE project=? AND topic=category AND correct=1) FROM errors WHERE project=? GROUP BY category ORDER BY SUM(occurrences) DESC", [project,project,project]); defer { sqlite3_finalize(s) }
        var result: [TopicStat] = []
        while sqlite3_step(s) == SQLITE_ROW { result.append(TopicStat(topic: String(cString: sqlite3_column_text(s,0)), occurrences: Int(sqlite3_column_int(s,1)), answered: Int(sqlite3_column_int(s,2)), correct: Int(sqlite3_column_int(s,3)))) }
        return result
    }
    public func answer(id: String, project: String, topic: String, correct: Bool) throws {
        try run("INSERT OR IGNORE INTO attempts VALUES(?,?,?,?,?)", [id,project,topic,correct ? "1":"0",String(Date().timeIntervalSince1970)])
    }
    public func erase() throws {
        try execute("PRAGMA secure_delete=ON; BEGIN IMMEDIATE; DELETE FROM errors; DELETE FROM attempts; COMMIT; PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }
}

public enum LearningSelection {
    public static func problems(_ records:[ErrorRecord],resolved:Bool) -> [ErrorRecord] { records.filter { $0.active != resolved } }
    public static func context(_ stats:[TopicStat],topic:String?) -> [TopicStat] {
        guard let target=topic ?? stats.first?.topic, let stat=stats.first(where: { $0.topic==target }) else { return [] }
        return [stat]
    }
    public static func references(_ records:[ErrorRecord],topic:String?) -> [Diagnostic] {
        guard let topic else { return [] }
        return records.filter { $0.diagnostic.category==topic }.sorted {
            if $0.active != $1.active { return $0.active }
            return ($0.diagnostic.file,$0.diagnostic.line,$0.id)<($1.diagnostic.file,$1.diagnostic.line,$1.id)
        }.map(\.diagnostic)
    }
}
