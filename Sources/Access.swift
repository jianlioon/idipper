import AppKit

/// Real user home (sandbox redirects homeDirectoryForCurrentUser into the container).
let realHome: URL = {
    if let pw = getpwuid(getuid()), let d = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: d)) }
    return FileManager.default.homeDirectoryForCurrentUser
}()

/// App Sandbox folder access: security-scoped bookmarks for folders the user granted.
enum Access {
    static let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    private static let key = "grantedFolders"
    private static var active: [URL] = []
    private static var asked: Set<String> = []

    static func restore() {
        guard sandboxed else { return }
        var keep: [Data] = []
        for d in (UserDefaults.standard.array(forKey: key) as? [Data]) ?? [] {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               u.startAccessingSecurityScopedResource() {
                active.append(u)
                keep.append(stale ? ((try? u.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? d) : d)
            }
        }
        UserDefaults.standard.set(keep, forKey: key)
    }

    static func covered(_ path: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return active.contains { p == $0.path || p.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
    }

    private static func usable(_ dir: URL, write: Bool) -> Bool {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: dir.path)) != nil else { return false }
        return !write || fm.isWritableFile(atPath: dir.path)
    }

    /// Ensure access to a folder; asks the user once per folder if needed. Returns true if usable.
    @discardableResult
    static func ensure(_ dir: URL, write: Bool = false) -> Bool {
        guard sandboxed else { return true }
        var d = dir.standardizedFileURL
        while !FileManager.default.fileExists(atPath: d.path) && d.path != "/" { d = d.deletingLastPathComponent() }
        if usable(d, write: write) { return true }
        if covered(d.path) || asked.contains(d.path) { return false }
        asked.insert(d.path)
        return request(d)
    }

    @discardableResult
    static func request(_ dir: URL) -> Bool {
        let run = { () -> Bool in
            let p = NSOpenPanel()
            p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
            p.directoryURL = dir.deletingLastPathComponent()
            p.canCreateDirectories = false
            NSApp.activate(ignoringOtherApps: true)
            p.message = LF("iDipper 需要访问「%@」才能继续。请点「授权访问」（选择上层文件夹，例如个人文件夹，可一次授权全部）。", dir.path)
            p.prompt = L("授权访问")
            let r = p.runModal()
            NSLog("iDipper access panel result=%ld url=%@", r.rawValue, p.url?.path ?? "nil")
            guard r == .OK, let u = p.url else { return false }
            return grant(u)
        }
        if Thread.isMainThread { return run() }
        return DispatchQueue.main.sync(execute: run)
    }

    @discardableResult
    static func grant(_ u: URL) -> Bool {
        guard sandboxed else { return true }
        _ = u.startAccessingSecurityScopedResource(); active.append(u)
        guard let d = try? u.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { NSLog("iDipper bookmark failed"); return true }
        var all = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        all.append(d); UserDefaults.standard.set(all, forKey: key)
        return true
    }

    /// Check every absolute path in a 7zz argument list (archive, -o output, source files).
    static func ensure(args: [String], cwd: URL?) {
        guard sandboxed else { return }
        if let c = cwd { ensure(c, write: true) }
        for a in args {
            var p = a
            if p.hasPrefix("-o") { p.removeFirst(2); if p.hasPrefix("/") { ensure(URL(fileURLWithPath: p), write: true) }; continue }
            guard p.hasPrefix("/"), !p.hasPrefix(Bundle.main.bundlePath), !p.hasPrefix(NSTemporaryDirectory()) else { continue }
            let u = URL(fileURLWithPath: p)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            if exists && FileManager.default.isReadableFile(atPath: p) && FileManager.default.isWritableFile(atPath: u.deletingLastPathComponent().path) { continue }
            ensure(isDir.boolValue ? u : u.deletingLastPathComponent(), write: true)
        }
    }
}
