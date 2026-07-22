import Foundation

/// Watches a file or directory for changes via a `DispatchSource` and emits ticks on an
/// `AsyncStream`. Used to live-refresh the active task file's tabs (and to notice new/changed
/// task files in the tasks directory) while Claude Code writes.
///
/// IMPORTANT (kanban-code crash rule): the DispatchSource is created on a background queue,
/// never under `@MainActor`, otherwise EXC_BREAKPOINT can occur.
public final class TaskFileWatcher: @unchecked Sendable {
    public let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "kanban.taskfile.watch", qos: .utility)
    private var source: (any DispatchSourceFileSystemObject)?
    private var fileDescriptor: Int32 = -1

    public init(path: String) {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.events = stream
        self.continuation = continuation
        queue.async { [weak self] in self?.start(path: path) }
    }

    private func start(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.continuation.yield(())
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    public func cancel() {
        source?.cancel()
        source = nil
        continuation.finish()
    }

    deinit {
        source?.cancel()
        continuation.finish()
    }
}
