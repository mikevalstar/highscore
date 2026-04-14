import Foundation
import CoreServices

/// Watches a set of filesystem paths for changes and fires a callback.
///
/// Wraps `FSEventStream` (the macOS kernel-event API used by Spotlight, Time Machine,
/// etc.). Events are coalesced by the kernel and further coalesced by the stream's
/// `latency` parameter — a burst of writes to the same file produces a single
/// callback. Callers should debounce on top of this for a second safety margin.
///
/// Watching a directory is recursive — descendant file writes fire events on the
/// stream. Non-existent paths are skipped at start time (FSEvents rejects them).
/// Usage:
/// ```swift
/// let watcher = FileWatcher(paths: ["/Users/x/.claude/projects"]) { [weak self] in
///     self?.onChange()
/// }
/// watcher.start()
/// ```
///
/// Start/stop are not thread-safe; call them from a single thread (typically main).
/// The `onChange` callback fires on the provided dispatch queue (default: utility).
final class FileWatcher {
    private let paths: [String]
    private let latency: TimeInterval
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    /// - Parameters:
    ///   - paths: Paths to watch recursively. Non-existent paths are filtered at start.
    ///   - latency: Seconds to coalesce events before firing the callback (default 1.0).
    ///     Acts as a first-pass debounce at the kernel level.
    ///   - queue: Queue on which `onChange` fires.
    ///   - onChange: Callback invoked for each coalesced batch of events.
    init(
        paths: [String],
        latency: TimeInterval = 1.0,
        queue: DispatchQueue = DispatchQueue(label: "org.mikevalstar.highscore.watcher", qos: .utility),
        onChange: @escaping () -> Void
    ) {
        self.paths = paths
        self.latency = latency
        self.queue = queue
        self.onChange = onChange
    }

    /// Starts watching. Idempotent — calling again while running is a no-op.
    /// Paths that don't exist at call time are filtered out.
    func start() {
        guard stream == nil else {
            Log.watcher.debug("start() called but watcher already running")
            return
        }

        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else {
            Log.watcher.info("No existing paths to watch — watcher not started")
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, _, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            Log.watcher.debug("FSEvents callback fired with \(numEvents) event(s)")
            watcher.onChange()
        }

        // FileEvents → per-file granularity (not just dir-level)
        // NoDefer → fire first event immediately instead of waiting for latency window
        // IgnoreSelf → don't report our own writes (we don't write to watched paths, but defensive)
        let flags: FSEventStreamCreateFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagIgnoreSelf
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Log.watcher.error("FSEventStreamCreate returned nil for \(existing.count) path(s)")
            return
        }

        FSEventStreamSetDispatchQueue(newStream, queue)

        guard FSEventStreamStart(newStream) else {
            Log.watcher.error("FSEventStreamStart failed")
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return
        }

        stream = newStream
        let pathList = existing.joined(separator: ", ")
        Log.watcher.notice(
            "File watcher started: \(existing.count) path(s), latency=\(String(format: "%.2f", self.latency))s — \(pathList, privacy: .public)"
        )
        if existing.count < paths.count {
            Log.watcher.info("Skipped \(self.paths.count - existing.count) non-existent path(s)")
        }
    }

    /// Stops watching. Idempotent.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        Log.watcher.notice("File watcher stopped")
    }

    deinit {
        if stream != nil {
            stop()
        }
    }
}
