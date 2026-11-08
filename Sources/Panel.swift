import SwiftUI
import AppKit
import Darwin

let sortKeys: [PartialKeyPath<Entry>] = [\Entry.name, \Entry.size, \Entry.packed, \Entry.modified, \Entry.created, \Entry.attrs, \Entry.crc, \Entry.method, \Entry.encrypted, \Entry.comment, \Entry.typeKey]
func comparator(_ i: Int, _ asc: Bool) -> KeyPathComparator<Entry> {
    let o: SortOrder = asc ? .forward : .reverse
    switch i {
    case 1: return KeyPathComparator(\Entry.size, order: o)
    case 2: return KeyPathComparator(\Entry.packed, order: o)
    case 3: return KeyPathComparator(\Entry.modified, order: o)
    case 4: return KeyPathComparator(\Entry.created, order: o)
    case 5: return KeyPathComparator(\Entry.attrs, order: o)
    case 6: return KeyPathComparator(\Entry.crc, order: o)
    case 7: return KeyPathComparator(\Entry.method, order: o)
    case 8: return KeyPathComparator(\Entry.encrypted, order: o)
    case 9: return KeyPathComparator(\Entry.comment, order: o)
    case 10: return KeyPathComparator(\Entry.typeKey, order: o)
    default: return KeyPathComparator(\Entry.name, comparator: .localizedStandard, order: o)
    }
}

final class Panel: ObservableObject {
    let idx: Int
    @Published var dir: URL { didSet { UserDefaults.standard.set(dir.path, forKey: "pane\(idx)dir") } }
    @Published var archive: URL? = nil
    @Published var inner = ""
    @Published var entries: [Entry] = []
    @Published var selection = Set<String>()
    @Published var address = ""
    @Published var sortOrder: [KeyPathComparator<Entry>] { didSet { saveSort(); applySort() } }
    var raw: [Entry] = []
    var archiveItems: [ArcItem] = []
    var archiveHeader: [String: String] = [:]
    var password: String? = nil
    var backStack: [String] = []
    var fwdStack: [String] = []
    var lastLoc = ""
    var navigating = false
    var archiveStamp: (mtime: TimeInterval, size: Int64)?
    var listGen = 0
    func noteLocation() {
        let loc = location
        if loc != lastLoc {
            if !lastLoc.isEmpty && !navigating { backStack.append(lastLoc); fwdStack = [] }
            lastLoc = loc
        }
    }
    func goBack() { guard let l = backStack.popLast() else { return }; fwdStack.append(location); navigating = true; go(l); navigating = false }
    func goForward() { guard let l = fwdStack.popLast() else { return }; backStack.append(location); navigating = true; go(l); navigating = false }

    init(idx: Int) {
        self.idx = idx
        let saved = UserDefaults.standard.string(forKey: "pane\(idx)dir")
        dir = (saved.flatMap { isDirPath($0) ? URL(fileURLWithPath: $0) : nil }) ?? realHome
        let k = UserDefaults.standard.integer(forKey: "pane\(idx)sort")
        let asc = UserDefaults.standard.object(forKey: "pane\(idx)asc") as? Bool ?? true
        sortOrder = [comparator(k, asc)]
        refresh()
    }
    func saveSort() {
        guard let c = sortOrder.first else { return }
        let i = sortKeys.firstIndex(where: { $0 == c.keyPath }) ?? 0
        UserDefaults.standard.set(i, forKey: "pane\(idx)sort"); UserDefaults.standard.set(c.order == .forward, forKey: "pane\(idx)asc")
    }
    func sortBy(_ i: Int) {
        let cur = sortOrder.first
        var same = false
        if let c = cur { same = sortKeys.firstIndex(where: { k in k == c.keyPath }) == i }
        sortOrder = [comparator(i, same ? cur?.order != .forward : true)]
    }

    var location: String { archive.map { $0.path + (inner.isEmpty ? "" : "/" + inner) } ?? dir.path }
    var selected: [Entry] { entries.filter { selection.contains($0.id) && !$0.isParent } }
    var selectedURLs: [URL] { selected.map { URL(fileURLWithPath: $0.path) } }

    func applySort() {
        let s = raw.sorted(using: sortOrder)
        var out = s.filter { $0.isDir } + s.filter { !$0.isDir }
        if Prefs.shared.showDotDot && (archive != nil || dir.path != "/") {
            out.insert(Entry(name: "..", path: "\u{1}parent", isDir: true, isParent: true), at: 0)
        }
        entries = out
    }

    func refresh(force: Bool = false) {
        let keep = selection
        if let a = archive {
            if force || archiveChanged(a) { listArchive(a) } else { showInner() }
            selection = keep.intersection(Set(entries.map { $0.id }))
        } else {
            listFS(keepSelection: keep)
        }
    }

    func archiveChanged(_ u: URL) -> Bool {
        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let m = v?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let s = Int64(v?.fileSize ?? 0)
        if let old = archiveStamp, old.mtime == m, old.size == s { return false }
        archiveStamp = (m, s)
        return true
    }

    func stampArchive(_ u: URL) {
        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        archiveStamp = (v?.contentModificationDate?.timeIntervalSince1970 ?? 0, Int64(v?.fileSize ?? 0))
    }

    func listFS(keepSelection: Set<String>? = nil) {
        address = dir.path; noteLocation()
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isHiddenKey]
        let opts: FileManager.DirectoryEnumerationOptions = Prefs.shared.showHidden ? [] : [.skipsHiddenFiles]
        let d = dir
        listGen += 1
        let gen = listGen
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: keys, options: opts))
            if items == nil && Access.sandboxed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    if Access.ensure(d), let self, self.listGen == gen, self.dir == d { self.refresh() }
                }
            }
            let listed: [URL] = items ?? []
            let mapped: [Entry] = listed.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                let isDir = v?.isDirectory ?? false
                var st = stat()
                let perm = stat(u.path, &st) == 0 ? Int(st.st_mode & 0o777) : 0
                return Entry(name: u.lastPathComponent, path: u.path, isDir: isDir, size: isDir ? -1 : Int64(v?.fileSize ?? 0),
                             modified: v?.contentModificationDate.map { dateFmt.string(from: $0) } ?? "",
                             created: v?.creationDate.map { dateFmt.string(from: $0) } ?? "",
                             attrs: (isDir ? "D " : "") + String(perm, radix: 8))
            }
            DispatchQueue.main.async {
                guard let self, self.listGen == gen, self.dir == d, self.archive == nil else { return }
                self.raw = mapped
                self.applySort()
                if let keep = keepSelection {
                    self.selection = keep.intersection(Set(self.entries.map { $0.id }))
                }
            }
        }
    }

    @discardableResult
    func openArchive(_ u: URL, quiet: Bool = false) -> Bool {
        password = nil
        var (code, out) = Runner.runSync(["l", "-slt", "-p", u.path])
        if code != 0 && (out.contains("password") || out.contains("encrypted")) {
            guard let pw = askPassword(u.lastPathComponent) else { return false }
            password = pw
            (code, out) = Runner.runSync(["l", "-slt", "-p" + pw, u.path])
        }
        if code != 0 { if !quiet { msgBox(L("无法作为压缩包打开"), String(out.suffix(1500))) }; return false }
        let r = parseSLT(out); archiveItems = r.items; archiveHeader = r.header
        stampArchive(u)
        archive = u; inner = ""; dir = u.deletingLastPathComponent()
        selection = []
        showInner()
        AppModel.shared.pushHistory(u.path)
        return true
    }

    func listArchive(_ u: URL) {
        let (code, out) = Runner.runSync(["l", "-slt", "-p" + (password ?? ""), u.path])
        if code == 0 { let r = parseSLT(out); archiveItems = r.items; archiveHeader = r.header; stampArchive(u) }
        showInner()
    }

    func showInner() {
        guard let a = archive else { return }
        address = location; noteLocation()
        let prefix = inner.isEmpty ? "" : inner + "/"
        var map: [String: Entry] = [:]
        for it in archiveItems where it.path.hasPrefix(prefix) && it.path != inner {
            let rest = String(it.path.dropFirst(prefix.count))
            let comps = rest.split(separator: "/", maxSplits: 1)
            guard let first = comps.first else { continue }
            let name = String(first)
            if comps.count > 1 {
                if map[name] == nil { map[name] = Entry(name: name, path: prefix + name, isDir: true) }
            } else {
                map[name] = Entry(name: name, path: it.path, isDir: it.isDir, size: it.isDir ? -1 : it.size,
                                  packed: it.isDir ? -1 : it.packed, modified: it.modified, created: it.created, attrs: it.attrs,
                                  crc: it.crc, method: it.method, encrypted: it.encrypted, comment: it.comment)
            }
        }
        raw = Array(map.values)
        _ = a
        applySort()
    }

    func enter(_ e: Entry) {
        if e.isParent { up(); return }
        if archive != nil {
            if e.isDir { inner = e.path; selection = []; showInner() } else { AppModel.shared.openInnerExternally(self, [e]) }
            return
        }
        let u = URL(fileURLWithPath: e.path)
        if e.isDir { setDir(u) }
        else if isArchiveURL(u) { if !openArchive(u, quiet: true) { NSWorkspace.shared.open(u) } }
        else { NSWorkspace.shared.open(u) }
    }

    func setDir(_ u: URL) {
        archive = nil; archiveItems = []; archiveStamp = nil; password = nil; inner = ""
        dir = u; selection = []; listFS()
        AppModel.shared.pushHistory(u.path)
    }

    func up() {
        if archive != nil {
            if inner.isEmpty {
                let name = archive!.path; setDir(archive!.deletingLastPathComponent()); selection = [name]
            } else {
                let old = inner; inner = (inner as NSString).deletingLastPathComponent; showInner(); selection = [old]
            }
        } else if dir.path != "/" {
            let old = dir.path; setDir(dir.deletingLastPathComponent()); selection = [old]
        }
    }

    func go(_ text: String) {
        let p = (text as NSString).expandingTildeInPath
        if isDirPath(p) { setDir(URL(fileURLWithPath: p)); return }
        if FileManager.default.fileExists(atPath: p) { openArchive(URL(fileURLWithPath: p)); return }
        // path inside archive
        var comp = p
        while comp != "/" && !comp.isEmpty {
            comp = (comp as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: comp) && !isDirPath(comp) {
                if openArchive(URL(fileURLWithPath: comp)) { inner = String(p.dropFirst(comp.count + 1)); showInner() }
                return
            }
        }
        msgBox(L("路径不存在"), p)
    }
}
