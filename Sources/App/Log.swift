import os

/// Centralized loggers using Apple's os.Logger.
/// View in Console.app: filter by subsystem "com.highscore.app"
enum Log {
    static let app = Logger(subsystem: "com.highscore.app", category: "app")
    static let scores = Logger(subsystem: "com.highscore.app", category: "scores")
    static let reader = Logger(subsystem: "com.highscore.app", category: "reader")
    static let overlay = Logger(subsystem: "com.highscore.app", category: "overlay")
    static let settings = Logger(subsystem: "com.highscore.app", category: "settings")
    static let opencode = Logger(subsystem: "com.highscore.app", category: "opencode")
    static let codex = Logger(subsystem: "com.highscore.app", category: "codex")
    static let copilot = Logger(subsystem: "com.highscore.app", category: "copilot")
}
