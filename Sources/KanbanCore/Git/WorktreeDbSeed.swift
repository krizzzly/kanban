import Foundation

/// Info about the DB dump staged in a worktree's MySQL init dir (`iwf worktree create` places it at
/// `<initDir>/00_dev-dump.sql[.gz]`, auto-imported on first DB boot). The file name/header don't
/// encode the source (always `00_dev-dump.*`, mysqldump host is `localhost`), so only path/size/mtime
/// are meaningful — shown as a freshness hint in the Worktree tab.
public struct StagedDbDump: Sendable, Hashable {
    public let fileName: String
    public let sizeBytes: Int64
    public let modified: Date

    public init(fileName: String, sizeBytes: Int64, modified: Date) {
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.modified = modified
    }
}

public enum WorktreeDbSeed {
    /// iwf's default `dbInitDir` (relative to the worktree root).
    public static let defaultInitSubdir = "docker/run/data/dockerinit.d/mysql"

    /// The newest staged `*.sql` / `*.sql.gz` dump in the worktree's init dir, or nil if none.
    public static func staged(worktreePath: String, initSubdir: String = defaultInitSubdir) -> StagedDbDump? {
        let dir = URL(fileURLWithPath: worktreePath).appendingPathComponent(initSubdir)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }

        let newest = entries
            .filter { $0.lastPathComponent.hasSuffix(".sql") || $0.lastPathComponent.hasSuffix(".sql.gz") }
            .compactMap { url -> StagedDbDump? in
                guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let date = v.contentModificationDate else { return nil }
                return StagedDbDump(fileName: url.lastPathComponent,
                                    sizeBytes: Int64(v.fileSize ?? 0), modified: date)
            }
            .max { $0.modified < $1.modified }
        return newest
    }
}
