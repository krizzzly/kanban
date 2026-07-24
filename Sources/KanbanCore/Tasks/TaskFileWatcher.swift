import Foundation

/// Watches a file for changes via a `DispatchSource` and emits ticks on an `AsyncStream`. Used to
/// live-refresh the active task file / review file while Claude Code writes.
///
/// Robust against **atomic saves** (write-temp + `rename`, as Claude's Write/Edit and most editors
/// do): those replace the file's inode, which would leave an fd-based watch permanently deaf after
/// the first change. On a `.rename`/`.delete` event we emit one tick (so the new content loads) and
/// then **re-arm** the watch on the same path.
///
/// IMPORTANT (kanban-code crash rule): the DispatchSource is created on a background queue, never
/// under `@MainActor`, otherwise EXC_BREAKPOINT can occur.
public final class TaskFileWatcher: @unchecked Sendable {
    public let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "kanban.taskfile.watch", qos: .utility)
    private let path: String
    private var source: (any DispatchSourceFileSystemObject)?
    private var stopped = false

    public init(path: String) {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.events = stream
        self.continuation = continuation
        self.path = path
        queue.async { [weak self] in self?.start() }
    }

    /// Opens the path and arms a DispatchSource. On open failure (brief window during an atomic
    /// rename) it retries a bounded number of times before giving up.
    private func start(retriesLeft: Int = 10) {
        guard !stopped else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            if retriesLeft > 0 {
                queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.start(retriesLeft: retriesLeft - 1) }
            }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            self.continuation.yield(())
            if flags.contains(.rename) || flags.contains(.delete) {
                self.rearm()   // inode was replaced (atomic save) → re-watch the path
            }
        }
        src.setCancelHandler { close(fd) }   // capture this fd; closing is decoupled from re-arm
        source = src
        src.resume()
    }

    private func rearm() {
        guard !stopped else { return }
        source?.cancel()   // closes the stale fd via its cancel handler
        source = nil
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.start() }
    }

    public func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.source?.cancel()
            self.source = nil
        }
        continuation.finish()
    }

    deinit {
        source?.cancel()
        continuation.finish()
    }
}
