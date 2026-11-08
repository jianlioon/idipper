import SwiftUI
import AppKit

struct AddRequest: Identifiable {
    let id = UUID()
    var files: [URL]
    var cwd: URL
    var archivePath: String
    var format = "7z"
    var existing = false
    var names: [String]? = nil
    var password = ""
    var deleteSource = false
    var originals: [URL] = []
}
struct ExtractRequest: Identifiable {
    let id = UUID()
    var archives: [URL]
    var items: [String]
    var dest: String
    var password: String
}

final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var panels: [Panel] = []
    @Published var active = 0
    @Published var addReq: AddRequest? = nil
    @Published var extractReq: ExtractRequest? = nil
    @Published var history: [String] = UserDefaults.standard.stringArray(forKey: "history") ?? []
    let runner = Runner()
    let prefs = Prefs.shared
    var internalDrag = false

    init() {}
    func setup() { if panels.isEmpty { panels = [Panel(idx: 0), Panel(idx: 1)] } }

    var cur: Panel { panels[prefs.dual ? active : 0] }
    var other: Panel? { prefs.dual ? panels[1 - active] : nil }

    func refreshAll(force: Bool = false) { panels.forEach { $0.refresh(force: force) } }
    func refreshHidden() {
        panels.forEach { p in
            if p.archive == nil { p.listFS() } else { p.showInner() }
        }
    }
    func pushHistory(_ p: String) {
        history.removeAll { $0 == p }; history.insert(p, at: 0)
        if history.count > 40 { history.removeLast(history.count - 40) }
        UserDefaults.standard.set(history, forKey: "history")
    }
    func switchPane() { guard prefs.dual else { return }; active = 1 - active; focusPane(active) }
    func toggleDual() { prefs.dual.toggle(); if !prefs.dual { active = 0 }; objectWillChange.send() }
    func focusPane(_ i: Int) {
        DispatchQueue.main.async {
            guard let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) ?? NSApp.mainWindow,
                  let cv = w.contentView else { return }
            var found: [NSView] = []
            func walk(_ v: NSView) { if v is NSTableView || v is NSCollectionView { found.append(v) } else { v.subviews.forEach(walk) } }
            walk(cv)
            found.sort { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            if i < found.count { w.makeFirstResponder(found[i]) }
        }
    }

    // MARK: open
    func openSelected() { if let e = cur.entries.first(where: { cur.selection.contains($0.id) }) { cur.enter(e) } }
    func openInside() {
        guard let e = cur.selected.first else { return }
        if cur.archive == nil && !e.isDir { cur.openArchive(URL(fileURLWithPath: e.path)) } else { cur.enter(e) }
    }
    func openOutside() {
        let s = cur.selected; guard !s.isEmpty else { return }
        if cur.archive != nil { openInnerExternally(cur, s) } else { s.forEach { NSWorkspace.shared.open(URL(fileURLWithPath: $0.path)) } }
    }
    func extractToTemp(_ p: Panel, _ items: [Entry]) -> URL? {
        guard let a = p.archive else { return nil }
        let tmp = prefs.tempDir()
        let (code, out) = Runner.runSync(["x", a.path, "-o" + tmp.path, "-aoa", "-y", "-p" + (p.password ?? ""), "--"] + items.map { $0.path })
        if code != 0 { msgBox(L("解压失败"), String(out.suffix(1200))); return nil }
        return tmp
    }
    func openInnerExternally(_ p: Panel, _ items: [Entry]) {
        guard let a = p.archive else { return }
        let tmp = prefs.tempDir()
        runner.run(title: LF("正在解压 %@", "\(items.first?.name ?? "")"), args: ["x", a.path, "-o" + tmp.path, "-aoa", "-p" + (p.password ?? ""), "--"] + items.map { $0.path }) { code, out in
            if code == 0 { items.forEach { NSWorkspace.shared.open(tmp.appendingPathComponent($0.path)) } }
            else if code != -2 { msgBox(L("解压失败"), String(out.suffix(1500))) }
        }
    }
    /// Files to drag out: real file or extracted temp copy
    func dragURL(_ p: Panel, _ e: Entry) -> URL? {
        if e.isParent { return nil }
        internalDrag = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.internalDrag = false }
        if p.archive == nil { return URL(fileURLWithPath: e.path) }
        guard let tmp = extractToTemp(p, [e]) else { return nil }
        return tmp.appendingPathComponent(e.path)
    }

    // MARK: add / extract / test
    func showAdd(_ files: [URL]? = nil) {
        let p = cur
        if p.archive != nil && files == nil { msgBox(L("添加"), L("当前在压缩包内。请把文件拖进来，或在另一栏选中文件后按 F5。")); return }
        let fs = files ?? (p.selected.isEmpty ? [] : p.selectedURLs)
        guard !fs.isEmpty else { msgBox(L("添加"), L("请先选择要压缩的文件或文件夹。")); return }
        let parent = fs[0].deletingLastPathComponent()
        let base = fs.count == 1 ? (isDirPath(fs[0].path) ? fs[0].lastPathComponent : (fs[0].lastPathComponent as NSString).deletingPathExtension) : parent.lastPathComponent
        presentAdd(AddRequest(files: fs, cwd: parent, archivePath: parent.appendingPathComponent(base + ".7z").path))
    }
    func showExtract(destOverride: String? = nil) {
        let p = cur
        if let a = p.archive {
            let items = p.selected.map { $0.path }
            extractReq = ExtractRequest(archives: [a], items: items, dest: destOverride ?? defaultDest(a, multi: false), password: p.password ?? "")
        } else {
            let arcs = p.selected.filter { !$0.isDir }.map { URL(fileURLWithPath: $0.path) }
            guard !arcs.isEmpty else { msgBox(L("解压"), L("请先选择压缩包。")); return }
            extractReq = ExtractRequest(archives: arcs, items: [], dest: destOverride ?? defaultDest(arcs[0], multi: arcs.count > 1), password: "")
        }
    }
    func defaultDest(_ a: URL, multi: Bool) -> String {
        let parent = a.deletingLastPathComponent()
        if multi { return parent.appendingPathComponent("*").path }
        let d = parent.appendingPathComponent(archiveBaseName(a)).path
        if FileManager.default.fileExists(atPath: d) && !isDirPath(d) { return parent.path }
        return d
    }
    func test() {
        let p = cur
        var arcs: [URL] = []
        if let a = p.archive { arcs = [a] } else { arcs = p.selected.filter { !$0.isDir }.map { URL(fileURLWithPath: $0.path) } }
        guard !arcs.isEmpty else { msgBox(L("测试"), L("请先选择压缩包。")); return }
        let args = ["t", "-an"] + arcs.map { "-ai!" + $0.path } + ["-p" + (p.password ?? "")]
        runner.run(title: LF("正在测试 %@", "\(arcs.count == 1 ? arcs[0].lastPathComponent : LF("%@ 个压缩包", "\(arcs.count)"))"), args: args, total: arcs.reduce(0) { $0 + treeSize($1) }) { code, out in
            if code == -2 { return }
            if code != 0 && (out.contains("Wrong password") || out.contains("encrypted")) {
                if let pw = askPassword(arcs[0].lastPathComponent) { p.password = pw; self.test() }; return
            }
            showText(code == 0 ? L("测试完成：没有发现错误") : L("测试发现错误"), out.components(separatedBy: "\n").filter { !$0.hasPrefix("7-Zip") }.joined(separator: "\n"))
        }
    }

    /// add files into archive (optionally inside folder `inner`), staging to temp if needed
    func addToArchive(_ arc: URL, files: [URL], inner: String, password: String?, deleteSource: Bool = false, done: (() -> Void)? = nil) {
        var cwd = files[0].deletingLastPathComponent()
        var names = files.map { $0.lastPathComponent }
        let sameParent = files.allSatisfy { $0.deletingLastPathComponent() == cwd }
        if !inner.isEmpty || !sameParent {
            let tmp = prefs.tempDir()
            let target = inner.isEmpty ? tmp : tmp.appendingPathComponent(inner)
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for f in files { try? FileManager.default.copyItem(at: f, to: target.appendingPathComponent(f.lastPathComponent)) }
            cwd = tmp
            names = inner.isEmpty ? files.map { $0.lastPathComponent } : [inner.split(separator: "/").first.map(String.init) ?? inner]
        }
        var req = AddRequest(files: files, cwd: cwd, archivePath: arc.path)
        req.format = formatFor(arc); req.existing = true; req.names = names
        req.password = password ?? ""; req.deleteSource = deleteSource
        req.originals = (cwd == files[0].deletingLastPathComponent()) ? [] : files
        presentAdd(req)
    }
    func formatFor(_ u: URL) -> String {
        ["7z": "7z", "zip": "zip", "tar": "tar", "gz": "gzip", "tgz": "gzip", "bz2": "bzip2", "xz": "xz", "wim": "wim"][u.pathExtension.lowercased()] ?? "7z"
    }
    func presentAdd(_ req: AddRequest) {
        bringAppToFront()
        if addReq != nil { addReq = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.addReq = req } } else { addReq = req }
    }

    // MARK: copy / move (F5 / F6)
    func copyMove(move: Bool, toPicked: Bool = false) {
        let p = cur; let sel = p.selected
        guard !sel.isEmpty else { msgBox(move ? L("移动") : L("复制"), L("请先选择项目。")); return }
        let o = toPicked ? nil : other
        // destination: other pane archive
        if let o, let oa = o.archive {
            if p.archive != nil {
                guard let tmp = extractToTemp(p, sel) else { return }
                let urls = sel.map { tmp.appendingPathComponent($0.path) }
                addToArchive(oa, files: urls, inner: o.inner, password: o.password)
            } else {
                addToArchive(oa, files: p.selectedURLs, inner: o.inner, password: o.password, deleteSource: move)
            }
            return
        }
        let defaultDest = o?.dir.path ?? p.dir.path
        let destStr: String?
        if toPicked { destStr = chooseFolder(move ? L("移动到：") : L("复制到："), start: p.dir)?.path }
        else { destStr = ask(move ? L("移动") : L("复制"), LF("%@ %@ 个项目到：", "\(move ? L("移动") : L("复制"))", "\(sel.count)"), defaultDest) }
        guard let ds = destStr, !ds.isEmpty else { return }
        let dest = URL(fileURLWithPath: (ds as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        if let a = p.archive {
            if move { msgBox(L("移动"), L("不能从压缩包中移动，已改为复制（解压）。")) }
            let prefix = p.inner.isEmpty ? "" : p.inner + "/"
            // extract keeping paths relative to current inner folder
            let tmp = prefs.tempDir()
            runner.run(title: L("正在解压"), args: ["x", a.path, "-o" + tmp.path, "-aoa", "-p" + (p.password ?? ""), "--"] + sel.map { $0.path }) { code, out in
                if code == 0 {
                    let srcs = sel.map { tmp.appendingPathComponent(prefix).appendingPathComponent($0.name) }
                    self.fsTransfer(srcs, to: dest, move: true)
                } else if code != -2 { msgBox(L("解压失败"), String(out.suffix(1500))) }
            }
            return
        }
        fsTransfer(p.selectedURLs, to: dest, move: move)
    }
    func fsTransfer(_ srcs: [URL], to dest: URL, move: Bool) {
        let fm = FileManager.default
        var overwriteAll: Bool? = nil
        var plan: [(URL, URL)] = []
        for s in srcs {
            let t = dest.appendingPathComponent(s.lastPathComponent)
            if s.standardizedFileURL == t.standardizedFileURL { continue }
            if fm.fileExists(atPath: t.path) {
                var ow = overwriteAll
                if ow == nil {
                    switch msgBox(L("确认文件替换"), LF("目标位置已存在「%@」，要替换吗？", "\(s.lastPathComponent)"), buttons: [L("是"), L("全是"), L("否"), L("全否"), L("取消")]) {
                    case 0: ow = true
                    case 1: ow = true; overwriteAll = true
                    case 2: ow = false
                    case 3: ow = false; overwriteAll = false
                    default: return
                    }
                }
                if ow == false { continue }
                try? fm.trashItem(at: t, resultingItemURL: nil)
            }
            plan.append((s, t))
        }
        DispatchQueue.global().async {
            var errs: [String] = []
            for (s, t) in plan {
                do { if move { try fm.moveItem(at: s, to: t) } else { try fm.copyItem(at: s, to: t) } }
                catch { errs.append(LF("%@：%@", "\(s.lastPathComponent)", "\(error.localizedDescription)")) }
            }
            DispatchQueue.main.async {
                if !errs.isEmpty { msgBox(L("部分项目失败"), errs.joined(separator: "\n")) }
                self.refreshAll()
            }
        }
    }

    // MARK: delete / rename / new
    func delete() {
        let p = cur; let sel = p.selected
        guard !sel.isEmpty else { return }
        if let arc = p.archive {
            guard confirm(L("确认删除"), LF("从压缩包中删除 %@ 个项目？此操作不可撤销。", "\(sel.count)"), ok: L("删除")) else { return }
            runner.run(title: L("正在删除"), args: ["d", arc.path, "-p" + (p.password ?? ""), "--"] + sel.map { $0.path }) { code, out in
                if code != 0 && code != -2 { msgBox(L("删除失败"), String(out.suffix(1500))) }
                p.refresh()
            }
        } else {
            guard confirm(L("确认删除"), LF("将 %@ 个项目移到废纸篓？", "\(sel.count)"), ok: L("删除")) else { return }
            for e in sel { try? FileManager.default.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil) }
            p.refresh()
        }
    }
    func rename() {
        let p = cur
        guard let e = p.selected.first else { return }
        guard let n = ask(L("重命名"), L("新名称："), e.name), !n.isEmpty, n != e.name, !n.contains("/") else { return }
        if let arc = p.archive {
            let prefix = p.inner.isEmpty ? "" : p.inner + "/"
            let newPath = prefix + n
            var pairs = [e.path, newPath]
            if e.isDir {
                pairs = []
                for it in p.archiveItems where it.path == e.path || it.path.hasPrefix(e.path + "/") {
                    pairs += [it.path, newPath + String(it.path.dropFirst(e.path.count))]
                }
            }
            runner.run(title: L("正在重命名"), args: ["rn", arc.path, "-p" + (p.password ?? ""), "--"] + pairs) { code, out in
                if code != 0 && code != -2 { msgBox(L("重命名失败"), String(out.suffix(1500))) }
                p.refresh(); p.selection = [newPath]
            }
        } else {
            let to = URL(fileURLWithPath: e.path).deletingLastPathComponent().appendingPathComponent(n)
            do { try FileManager.default.moveItem(atPath: e.path, toPath: to.path); p.refresh(); p.selection = [to.path] }
            catch { msgBox(L("重命名失败"), error.localizedDescription) }
        }
    }
    func newItem(folder: Bool) {
        let p = cur
        guard let n = ask(folder ? L("新建文件夹") : L("新建文件"), L("名称："), folder ? L("新建文件夹") : L("新建文本文档.txt")), !n.isEmpty, !n.contains("/") else { return }
        if let arc = p.archive {
            let tmp = prefs.tempDir().appendingPathComponent(n)
            if folder { try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true) }
            else { FileManager.default.createFile(atPath: tmp.path, contents: Data()) }
            addToArchive(arc, files: [tmp], inner: p.inner, password: p.password)
            return
        }
        let u = p.dir.appendingPathComponent(n)
        if FileManager.default.fileExists(atPath: u.path) { msgBox(L("已存在"), n); return }
        if folder { try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: false) }
        else { FileManager.default.createFile(atPath: u.path, contents: Data()) }
        p.refresh(); p.selection = [u.path]
    }

    // MARK: pasteboard
    func copyToPasteboard() {
        let p = cur; let sel = p.selected; guard !sel.isEmpty else { return }
        var urls: [URL] = []
        if p.archive != nil {
            guard let tmp = extractToTemp(p, sel) else { return }
            urls = sel.map { tmp.appendingPathComponent($0.path) }
        } else { urls = p.selectedURLs }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls as [NSURL])
    }
    func pasteFromPasteboard() {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        internalDrag = true
        handleDrop(urls, on: cur)
    }

    // MARK: selection
    func selectAll() { cur.selection = Set(cur.entries.filter { !$0.isParent }.map { $0.id }) }
    func selectNone() { cur.selection = [] }
    func invert() { let all = Set(cur.entries.filter { !$0.isParent }.map { $0.id }); cur.selection = all.subtracting(cur.selection) }
    func selectPattern(_ add: Bool) {
        guard let pat = ask(add ? L("选择") : L("取消选择"), L("通配符（如 *.txt）："), "*") else { return }
        let m = cur.entries.filter { !$0.isParent && fnmatch(pat, $0.name, FNM_CASEFOLD) == 0 }.map { $0.id }
        if add { cur.selection.formUnion(m) } else { cur.selection.subtract(m) }
    }

    // MARK: info / properties / comment
    func properties() {
        let p = cur; let sel = p.selected
        var t = ""
        if let a = p.archive {
            t += LF("压缩包：%@\n", "\(a.path)")
            for k in ["Type", "Physical Size", "Headers Size", "Method", "Solid", "Blocks", "Encrypted", "Volumes", "Comment"] {
                if let v = p.archiveHeader[k] { t += LF("  %@：%@\n", "\(k)", "\(v)") }
            }
            t += "\n"
        }
        let list = sel.isEmpty ? p.entries.filter { !$0.isParent } : sel
        if list.count == 1, let e = list.first {
            t += LF("名称：%@\n路径：%@\n", "\(e.name)", "\(e.path)")
            let sz = p.archive == nil ? treeSize(URL(fileURLWithPath: e.path)) : (e.isDir ? p.archiveItems.filter { $0.path.hasPrefix(e.path + "/") }.reduce(0) { $0 + max(0, $1.size) } : e.size)
            t += LF("大小：%@（%@）\n", "\(fmtSize(sz))", "\(fmtExact(sz))")
            if e.packed >= 0 { t += LF("压缩后大小：%@\n", "\(fmtSize(e.packed))") }
            t += LF("修改时间：%@\n创建时间：%@\n属性：%@\n", "\(e.modified)", "\(e.created)", "\(e.attrs)")
            if !e.crc.isEmpty { t += LF("CRC：%@\n", "\(e.crc)") }
            if !e.method.isEmpty { t += LF("方法：%@\n", "\(e.method)") }
            if !e.encrypted.isEmpty { t += LF("加密：%@\n", "\(e.encrypted)") }
            if !e.comment.isEmpty { t += LF("注释：%@\n", "\(e.comment)") }
            if p.archive == nil && !e.isDir && isArchiveURL(URL(fileURLWithPath: e.path)) {
                let (_, out) = Runner.runSync(["l", "-p", e.path])
                t += "\n" + out.components(separatedBy: "\n").filter { !$0.hasPrefix("7-Zip") }.joined(separator: "\n")
            }
        } else {
            let sz = p.archive == nil ? list.reduce(0) { $0 + treeSize(URL(fileURLWithPath: $1.path)) } : list.reduce(0) { $0 + max(0, $1.size) }
            t += LF("项目：%@（文件夹 %@，文件 %@）\n大小：%@（%@）\n", "\(list.count)", "\(list.filter { $0.isDir }.count)", "\(list.filter { !$0.isDir }.count)", "\(fmtSize(sz))", "\(fmtExact(sz))")
            if p.archive != nil { t += LF("压缩后大小：%@\n", "\(fmtSize(list.reduce(0) { $0 + max(0, $1.packed) }))") }
        }
        showText(L("属性"), t)
    }
    func comment() {
        let p = cur
        guard let a = p.archive else {
            if let e = p.selected.first, isArchiveURL(URL(fileURLWithPath: e.path)) {
                let (_, out) = Runner.runSync(["l", "-slt", "-p", e.path])
                let c = parseSLT(out).header["Comment"] ?? ""
                showText(LF("注释 - %@", "\(e.name)"), c.isEmpty ? L("（此压缩包没有注释）") : c)
            } else { msgBox(L("注释"), L("请先打开或选中一个压缩包。")) }
            return
        }
        let c = p.archiveHeader["Comment"] ?? ""
        showText(LF("注释 - %@", "\(a.lastPathComponent)"), (c.isEmpty ? L("（此压缩包没有注释）") : c) + L("\n\n说明：7zz 命令行不支持写入注释，这里只能查看。"))
    }

    // MARK: hash
    func hash(_ method: String) {
        let p = cur
        var urls = p.selectedURLs
        var cwd = p.dir
        if p.archive != nil {
            guard let tmp = extractToTemp(p, p.selected) else { return }
            let prefix = p.inner.isEmpty ? "" : p.inner + "/"
            urls = p.selected.map { tmp.appendingPathComponent(prefix + $0.name) }; cwd = tmp.appendingPathComponent(prefix)
        }
        guard !urls.isEmpty else { msgBox("CRC SHA", L("请先选择文件。")); return }
        hashFiles(urls, method: method, cwd: cwd)
    }
    func hashFiles(_ urls: [URL], method: String, cwd: URL) {
        let job = StreamJob()
        let m = method == "*" ? ["-scrc*"] : method.split(separator: ",").map { "-scrc" + $0 }
        let cwdPath = cwd.path.hasSuffix("/") ? cwd.path : cwd.path + "/"
        job.run(["h"] + m + ["--"] + urls.map { $0.path.hasPrefix(cwdPath) ? String($0.path.dropFirst(cwdPath.count)) : $0.path }, cwd: cwd)
        showWindow(LF("校验和 %@", "\(method == "*" ? L("全部") : method)"), HashView(job: job), size: NSSize(width: 760, height: 460))
    }

    // MARK: split / combine / compare
    func splitFile() {
        let p = cur
        guard p.archive == nil, let e = p.selected.first, !e.isDir else { msgBox(L("分割文件"), L("请选择一个文件。")); return }
        guard let s = ask(L("分割文件"), L("分卷大小（如 10M、100M、650M、4092M）："), "100M", combo: ["10M", "100M", "650M", "700M", "1000M", "4092M", "4480M"]),
              let size = parseSize(s), size > 0 else { return }
        let src = URL(fileURLWithPath: e.path)
        guard let destDir = ask(L("分割文件"), L("分割到："), other?.archive == nil ? (other?.dir.path ?? p.dir.path) : p.dir.path) else { return }
        DispatchQueue.global().async {
            var err: String? = nil; var n = 0
            do { n = try splitCore(src, destDir: destDir, size: size) } catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                if let err { msgBox(L("分割失败"), err) } else { msgBox(L("分割完成"), LF("已分割为 %@ 个文件。", "\(n)")) }
                self.refreshAll()
            }
        }
    }
    func parseSize(_ s: String) -> Int64? {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "B", with: "")
        guard let last = t.last else { return nil }
        let mult: Int64 = ["K": 1 << 10, "M": 1 << 20, "G": 1 << 30][String(last)] ?? 1
        let num = mult == 1 ? t : String(t.dropLast())
        return Int64(Double(num).map { $0 * Double(mult) } ?? 0)
    }
    func combineFiles() {
        let p = cur
        guard p.archive == nil, let e = p.selected.first, e.name.range(of: #"\.0*1$"#, options: .regularExpression) != nil else {
            msgBox(L("合并文件"), L("请选择第一个分卷文件（如 xxx.001）。")); return }
        let first = URL(fileURLWithPath: e.path)
        let ext = first.pathExtension; let base = first.deletingPathExtension()
        let parts = volumeParts(first)
        _ = ext
        guard let destDir = ask(L("合并文件"), LF("合并 %@ 个分卷到：", "\(parts.count)"), other?.archive == nil ? (other?.dir.path ?? p.dir.path) : p.dir.path) else { return }
        let out = URL(fileURLWithPath: destDir).appendingPathComponent(base.lastPathComponent)
        if FileManager.default.fileExists(atPath: out.path) && !confirm(L("文件已存在"), LF("%@\n要覆盖吗？", "\(out.path)"), ok: L("覆盖")) { return }
        DispatchQueue.global().async {
            var err: String? = nil
            do { try combineCore(parts, out: out) } catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                if let err { msgBox(L("合并失败"), err) } else { msgBox(L("合并完成"), LF("已合并 %@ 个分卷：\n%@", "\(parts.count)", "\(out.path)")) }
                self.refreshAll()
            }
        }
    }
    func compare() {
        var files: [String] = cur.archive == nil ? cur.selected.filter { !$0.isDir }.map { $0.path } : []
        if files.count == 1, let o = other, o.archive == nil, let f = o.selected.first(where: { !$0.isDir }) { files.append(f.path) }
        guard files.count == 2 else { msgBox(L("对比"), L("请选中两个文件（同一栏选两个，或两栏各选一个）。")); return }
        guard FileManager.default.fileExists(atPath: "/usr/bin/opendiff") else { msgBox(L("对比"), L("没有找到 opendiff（需要 Xcode 的 FileMerge）。")); return }
        let pr = Process(); pr.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff"); pr.arguments = files
        pr.standardOutput = FileHandle.nullDevice; pr.standardError = FileHandle.nullDevice
        try? pr.run()
    }

    // MARK: bookmarks
    func setBookmark(_ n: Int) { UserDefaults.standard.set(cur.location, forKey: "bm\(n)"); objectWillChange.send() }
    func gotoBookmark(_ n: Int) { if let s = UserDefaults.standard.string(forKey: "bm\(n)") { cur.go(s) } }
    func bookmark(_ n: Int) -> String? { UserDefaults.standard.string(forKey: "bm\(n)") }

    // MARK: drops
    func handleDrop(_ urls: [URL], on p: Panel) {
        guard !urls.isEmpty else { return }
        let isInternal = internalDrag; internalDrag = false
        if let a = p.archive {
            addToArchive(a, files: urls, inner: p.inner, password: p.password)
            return
        }
        if !isInternal && urls.count == 1 && isArchiveURL(urls[0]) && !isDirPath(urls[0].path) {
            p.openArchive(urls[0]); return
        }
        if !isInternal && urls.count == 1 && isDirPath(urls[0].path) && urls[0].deletingLastPathComponent() != p.dir {
            p.setDir(urls[0]); return
        }
        if urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == p.dir.standardizedFileURL }) { return }
        fsTransfer(urls, to: p.dir, move: false)
    }
    func openURLs(_ urls: [URL]) {
        guard let u = urls.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        let p = cur
        if isDirPath(u.path) && urls.count == 1 { p.setDir(u) }
        else if urls.count == 1 && isArchiveURL(u) { if !p.openArchive(u) { p.setDir(u.deletingLastPathComponent()) } }
        else { p.setDir(u.deletingLastPathComponent()); p.selection = Set(urls.map { $0.path }); showAdd(urls) }
    }

    // MARK: Finder services helpers
    func quickCompress(_ urls: [URL], ext: String) {
        guard let f = urls.first else { return }
        let parent = f.deletingLastPathComponent()
        let base = urls.count == 1 ? (isDirPath(f.path) ? f.lastPathComponent : (f.lastPathComponent as NSString).deletingPathExtension) : parent.lastPathComponent
        if cur.archive == nil { cur.setDir(parent); cur.selection = Set(urls.map { $0.path }) }
        var req = AddRequest(files: urls, cwd: parent, archivePath: parent.appendingPathComponent(base + "." + ext).path)
        req.format = ext
        presentAdd(req)
    }
    func quickExtract(_ urls: [URL], toSubfolder: Bool) {
        let arcs = urls.filter { !isDirPath($0.path) }
        guard let f = arcs.first else { return }
        let parent = f.deletingLastPathComponent()
        let dest = toSubfolder ? parent.appendingPathComponent("*").path : parent.path
        var pw = ""
        func go() {
            runner.run(title: LF("正在解压 %@", "\(f.lastPathComponent)"), args: ["x", "-an"] + arcs.map { "-ai!" + $0.path } + ["-o" + dest, "-aou", "-p" + pw], total: arcs.reduce(0) { $0 + treeSize($1) }) { code, out in
                if code != 0 && code != -2 && (out.contains("Wrong password") || out.contains("encrypted")) {
                    if let p = askPassword(f.lastPathComponent) { pw = p; go() }; return
                }
                if code != 0 && code != -2 { msgBox(L("解压出错"), String(out.suffix(1500))) }
                else if code == 0 { NSWorkspace.shared.activateFileViewerSelecting([toSubfolder ? parent.appendingPathComponent(archiveBaseName(f)) : f]) }
                self.refreshAll()
            }
        }
        go()
    }
}

func volumeParts(_ first: URL) -> [URL] {
    let ext = first.pathExtension; let base = first.deletingPathExtension()
    var parts: [URL] = []; var i = 1
    while true {
        let u = base.appendingPathExtension(String(format: "%0\(ext.count)d", i))
        if !FileManager.default.fileExists(atPath: u.path) { break }
        parts.append(u); i += 1
    }
    return parts
}
func splitCore(_ src: URL, destDir: String, size: Int64) throws -> Int {
    var n = 0
    let ih = try FileHandle(forReadingFrom: src)
    defer { try? ih.close() }
    while true {
        var written: Int64 = 0
        var oh: FileHandle? = nil
        while written < size {
            let d = ih.readData(ofLength: Int(min(Int64(8 << 20), size - written)))
            if d.isEmpty { break }
            if oh == nil {
                n += 1
                let out = URL(fileURLWithPath: destDir).appendingPathComponent(String(format: "%@.%03d", src.lastPathComponent, n))
                FileManager.default.createFile(atPath: out.path, contents: nil)
                oh = try FileHandle(forWritingTo: out)
            }
            oh!.write(d); written += Int64(d.count)
        }
        try oh?.close()
        if written < size || oh == nil { break }
    }
    return n
}
func combineCore(_ parts: [URL], out: URL) throws {
    FileManager.default.createFile(atPath: out.path, contents: nil)
    let oh = try FileHandle(forWritingTo: out)
    defer { try? oh.close() }
    for part in parts {
        let ih = try FileHandle(forReadingFrom: part)
        while true { let d = ih.readData(ofLength: 8 << 20); if d.isEmpty { break }; oh.write(d) }
        try ih.close()
    }
}
