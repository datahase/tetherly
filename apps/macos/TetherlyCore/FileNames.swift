import Foundation

/// File name rules per protocol/SPEC.md §7.
enum FileNames {
    static func sanitize(_ raw: String) -> String {
        let last = raw.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var cleaned = String(String.UnicodeScalarView(last.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f && $0 != ":" }))
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        var out = ""
        for ch in cleaned {
            if out.utf8.count + String(ch).utf8.count > 255 { break }
            out.append(ch)
        }
        return out.isEmpty ? "file" : out
    }

    /// `name`, or `stem (2).ext`, `stem (3).ext`: the first candidate for which `exists` is false.
    static func unique(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }

    /// Creates `dir/.tetherly-<tag>.partial` with O_EXCL|O_NOFOLLOW: fails rather than reuse or follow anything existing.
    static func createExclusiveTemp(in dir: URL, tag: String) -> (URL, FileHandle)? {
        let url = dir.appendingPathComponent(".tetherly-\(tag).partial")
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        return (url, FileHandle(fileDescriptor: fd, closeOnDealloc: true))
    }

    /// Moves temp → dir/name without ever replacing an existing file (RENAME_EXCL); returns the final name.
    static func publishExclusive(_ temp: URL, in dir: URL, name: String) -> String? {
        for _ in 0..<50 {
            let candidate = unique(name) { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
            if renamex_np(temp.path, dir.appendingPathComponent(candidate).path, UInt32(RENAME_EXCL)) == 0 { return candidate }
            if errno != EEXIST { return nil }
        }
        return nil
    }
}
