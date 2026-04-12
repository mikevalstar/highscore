import os

/// Centralized loggers using Apple's os.Logger.
/// View in Console.app: filter by subsystem "org.mikevalstar.highscore"
enum Log {
    static let app = Logger(subsystem: "org.mikevalstar.highscore", category: "app")
    static let scores = Logger(subsystem: "org.mikevalstar.highscore", category: "scores")
    static let reader = Logger(subsystem: "org.mikevalstar.highscore", category: "reader")
    static let overlay = Logger(subsystem: "org.mikevalstar.highscore", category: "overlay")
    static let settings = Logger(subsystem: "org.mikevalstar.highscore", category: "settings")
    static let opencode = Logger(subsystem: "org.mikevalstar.highscore", category: "opencode")
    static let codex = Logger(subsystem: "org.mikevalstar.highscore", category: "codex")
    static let copilot = Logger(subsystem: "org.mikevalstar.highscore", category: "copilot")
    static let cursor = Logger(subsystem: "org.mikevalstar.highscore", category: "cursor")
    static let rpg = Logger(subsystem: "org.mikevalstar.highscore", category: "rpg")
}
