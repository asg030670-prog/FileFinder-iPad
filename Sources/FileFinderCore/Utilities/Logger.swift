import Foundation
#if canImport(os)
import os
#endif

/// Severity of a log message.
public enum LogLevel: Int, Comparable, Sendable, CustomStringConvertible {
    case debug = 0
    case info
    case notice
    case warning
    case error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

/// A single captured log entry (kept in memory for diagnostics).
public struct LogEntry: Sendable, Identifiable {
    public let id = UUID()
    public let date: Date
    public let level: LogLevel
    public let category: String
    public let message: String
}

/// Lightweight logging facade.
///
/// On Apple platforms messages are forwarded to the unified logging system (`os.Logger`),
/// so they show up in Console.app / Xcode. On other platforms they are printed to stdout.
/// The most recent entries are also kept in memory (see `LogStore`) so they can be shown
/// in a diagnostics screen or attached to bug reports.
public struct FFLogger: Sendable {
    public static let subsystem = "com.filefinder.ipad"

    public let category: String

    #if canImport(os)
    private let osLogger: os.Logger
    #endif

    public init(category: String) {
        self.category = category
        #if canImport(os)
        self.osLogger = os.Logger(subsystem: FFLogger.subsystem, category: category)
        #endif
    }

    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func notice(_ message: @autoclosure () -> String) { log(.notice, message()) }
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }

    public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        guard level >= LogStore.shared.minimumLevel else { return }
        let text = message()
        LogStore.shared.append(LogEntry(date: Date(), level: level, category: category, message: text))
        #if canImport(os)
        switch level {
        case .debug: osLogger.debug("\(text, privacy: .private)")
        case .info: osLogger.info("\(text, privacy: .private)")
        case .notice: osLogger.notice("\(text, privacy: .private)")
        case .warning: osLogger.warning("\(text, privacy: .private)")
        case .error: osLogger.error("\(text, privacy: .private)")
        }
        #else
        if LogStore.shared.printsToConsole {
            print("[\(level)] [\(category)] \(text)")
        }
        #endif
    }
}

/// Thread-safe in-memory ring buffer with the most recent log entries.
public final class LogStore: @unchecked Sendable {
    public static let shared = LogStore()

    private let lock = NSLock()
    private var entries: [LogEntry] = []
    private var _minimumLevel: LogLevel = .debug
    private var _printsToConsole = false
    public let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    public var minimumLevel: LogLevel {
        get { lock.lock(); defer { lock.unlock() }; return _minimumLevel }
        set { lock.lock(); _minimumLevel = newValue; lock.unlock() }
    }

    /// Only used on platforms without unified logging.
    public var printsToConsole: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _printsToConsole }
        set { lock.lock(); _printsToConsole = newValue; lock.unlock() }
    }

    public func append(_ entry: LogEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()
    }

    public func recentEntries() -> [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }
}

/// Shared loggers per subsystem area.
public enum Log {
    public static let scanner = FFLogger(category: "Scanner")
    public static let index = FFLogger(category: "Index")
    public static let search = FFLogger(category: "Search")
    public static let operations = FFLogger(category: "FileOperations")
    public static let persistence = FFLogger(category: "Persistence")
    public static let ui = FFLogger(category: "UI")
}
