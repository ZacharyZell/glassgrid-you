import Darwin
import Foundation

public enum AgentFileIOError: Error, LocalizedError, Sendable {
    case symlinkDetected(String)
    case unsafeDirectoryPermissions(String)
    case wrongOwner(String)
    case openFailed(String, Int32)
    case writeFailed(String, Int32)
    case renameFailed(String, Int32)
    case fileTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .symlinkDetected(let path):
            return "Refused symlink at \(path)."
        case .unsafeDirectoryPermissions(let path):
            return "Unsafe directory permissions at \(path)."
        case .wrongOwner(let path):
            return "Directory or file not owned by current user at \(path)."
        case .openFailed(let path, let err):
            return "Failed to open \(path) (errno \(err))."
        case .writeFailed(let path, let err):
            return "Failed to write \(path) (errno \(err))."
        case .renameFailed(let path, let err):
            return "Failed to atomically replace \(path) (errno \(err))."
        case .fileTooLarge(let path):
            return "File exceeds safety size limit at \(path)."
        }
    }
}

/// Hardened POSIX file I/O using `lstat`, `O_NOFOLLOW`, `0600` creation, and atomic sibling rename.
public enum AgentSecureFileIO {
    /// Ensures `dirURL` exists as a non-symlink directory owned by `getuid()` with mode `0700`.
    public static func ensurePrivateDirectory(_ dirURL: URL) throws {
        let path = dirURL.path
        var st = stat()
        if lstat(path, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFLNK || (st.st_mode & S_IFMT) != S_IFDIR {
                throw AgentFileIOError.symlinkDetected(path)
            }
            if st.st_uid != getuid() {
                throw AgentFileIOError.wrongOwner(path)
            }
            if (st.st_mode & 0o077) != 0 {
                guard chmod(path, 0o700) == 0 else {
                    throw AgentFileIOError.unsafeDirectoryPermissions(path)
                }
            }
            return
        }

        // Create missing intermediate directories cleanly, then lock down leaf to 0700.
        try FileManager.default.createDirectory(
            at: dirURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if lstat(path, &st) != 0 || (st.st_mode & S_IFMT) != S_IFDIR {
            throw AgentFileIOError.symlinkDetected(path)
        }
        if st.st_uid != getuid() {
            throw AgentFileIOError.wrongOwner(path)
        }
        if (st.st_mode & 0o077) != 0 {
            guard chmod(path, 0o700) == 0 else {
                throw AgentFileIOError.unsafeDirectoryPermissions(path)
            }
        }
    }

    /// Reads an existing regular file safely using `O_RDONLY | O_NOFOLLOW` and `fstat` ownership checks.
    /// Returns `(data, mode)` or `nil` if the file does not exist.
    public static func readFileNoFollow(at url: URL, maxBytes: Int = 2_097_152) throws -> (data: Data, mode: mode_t)? {
        let path = url.path
        var lst = stat()
        if lstat(path, &lst) != 0 {
            if errno == ENOENT {
                return nil
            }
            throw AgentFileIOError.openFailed(path, errno)
        }
        if (lst.st_mode & S_IFMT) == S_IFLNK || (lst.st_mode & S_IFMT) != S_IFREG {
            throw AgentFileIOError.symlinkDetected(path)
        }
        if lst.st_uid != getuid() {
            throw AgentFileIOError.wrongOwner(path)
        }

        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw AgentFileIOError.openFailed(path, errno)
        }
        defer { Darwin.close(fd) }

        var fst = stat()
        guard fstat(fd, &fst) == 0 else {
            throw AgentFileIOError.openFailed(path, errno)
        }
        if (fst.st_mode & S_IFMT) != S_IFREG {
            throw AgentFileIOError.symlinkDetected(path)
        }
        if fst.st_uid != getuid() {
            throw AgentFileIOError.wrongOwner(path)
        }
        if fst.st_size > Int64(maxBytes) {
            throw AgentFileIOError.fileTooLarge(path)
        }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n < 0 {
                if errno == EINTR { continue }
                throw AgentFileIOError.openFailed(path, errno)
            }
            if n == 0 { break }
            if data.count + n > maxBytes {
                throw AgentFileIOError.fileTooLarge(path)
            }
            data.append(buf, count: n)
        }
        return (data, fst.st_mode & 0o777)
    }

    /// Refuses pre-existing symlinks at `targetURL` or `backupURL`, writes optional `0600` backup,
    /// writes sibling temp file with `O_CREAT | O_EXCL | O_NOFOLLOW` + `mode`, fsyncs, and atomically replaces `targetURL`.
    public static func writeAtomicSecureFile(
        data: Data,
        to targetURL: URL,
        mode: mode_t = 0o600,
        backupURL: URL? = nil,
        existingDataForBackup: Data? = nil
    ) throws {
        let parentDir = targetURL.deletingLastPathComponent()
        try ensureParentDirectoryChainExists(parentDir)
        try rejectSymlinkIfPresent(at: targetURL)

        if let backupURL {
            try rejectSymlinkIfPresent(at: backupURL)
            if let existingDataForBackup {
                try writeSingleFileNoFollow(data: existingDataForBackup, to: backupURL, mode: 0o600)
            }
        }

        let tmpURL = parentDir.appendingPathComponent(".\(targetURL.lastPathComponent).tmp-\(UUID().uuidString)")
        let tmpPath = tmpURL.path
        let fd = Darwin.open(tmpPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard fd >= 0 else {
            throw AgentFileIOError.openFailed(tmpPath, errno)
        }

        var didCommit = false
        defer {
            if !didCommit {
                _ = Darwin.unlink(tmpPath)
            }
        }

        do {
            try writeAll(fd: fd, data: data, path: tmpPath)
            _ = fchmod(fd, mode)
            _ = fsync(fd)
            Darwin.close(fd)
        } catch {
            Darwin.close(fd)
            throw error
        }

        if Darwin.rename(tmpPath, targetURL.path) != 0 {
            throw AgentFileIOError.renameFailed(targetURL.path, errno)
        }
        didCommit = true
    }

    private static func writeSingleFileNoFollow(data: Data, to url: URL, mode: mode_t) throws {
        try rejectSymlinkIfPresent(at: url)
        let path = url.path
        let tmpPath = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
            .path
        let fd = Darwin.open(tmpPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard fd >= 0 else {
            throw AgentFileIOError.openFailed(tmpPath, errno)
        }
        var committed = false
        defer {
            if !committed { _ = Darwin.unlink(tmpPath) }
        }
        do {
            try writeAll(fd: fd, data: data, path: tmpPath)
            _ = fchmod(fd, mode)
            _ = fsync(fd)
            Darwin.close(fd)
        } catch {
            Darwin.close(fd)
            throw error
        }
        if Darwin.rename(tmpPath, path) != 0 {
            throw AgentFileIOError.renameFailed(path, errno)
        }
        committed = true
    }

    private static func ensureParentDirectoryChainExists(_ dirURL: URL) throws {
        let path = dirURL.path
        var lst = stat()
        if lstat(path, &lst) == 0 {
            if (lst.st_mode & S_IFMT) == S_IFLNK || (lst.st_mode & S_IFMT) != S_IFDIR {
                throw AgentFileIOError.symlinkDetected(path)
            }
            if lst.st_uid != getuid() {
                throw AgentFileIOError.wrongOwner(path)
            }
            return
        }
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
    }

    private static func rejectSymlinkIfPresent(at url: URL) throws {
        var lst = stat()
        if lstat(url.path, &lst) == 0 {
            if (lst.st_mode & S_IFMT) == S_IFLNK || (lst.st_mode & S_IFMT) != S_IFREG {
                throw AgentFileIOError.symlinkDetected(url.path)
            }
            if lst.st_uid != getuid() {
                throw AgentFileIOError.wrongOwner(url.path)
            }
        } else if errno != ENOENT {
            throw AgentFileIOError.openFailed(url.path, errno)
        }
    }

    private static func writeAll(fd: Int32, data: Data, path: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let n = Darwin.write(fd, base.advanced(by: offset), rawBuffer.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw AgentFileIOError.writeFailed(path, errno)
                }
                if n == 0 {
                    throw AgentFileIOError.writeFailed(path, EIO)
                }
                offset += n
            }
        }
    }
}
