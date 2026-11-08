import SwiftUI
import AppKit
import UniformTypeIdentifiers

func L(_ s: String) -> String { Bundle.main.localizedString(forKey: s, value: s, table: nil) }
func LF(_ s: String, _ args: String...) -> String {
    var out = L(s); var i = 0
    while let r = out.range(of: "%@"), i < args.count { out.replaceSubrange(r, with: args[i]); i += 1 }
    return out
}

/// Bundled 7zz (Contents/MacOS/7zz) first; Homebrew copy only as a fallback.
let SEVENZ: String = {
    if let env = ProcessInfo.processInfo.environment["DIPPER_7ZZ"], FileManager.default.isExecutableFile(atPath: env) { return env }
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/7zz").path
    if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
    return "/opt/homebrew/bin/7zz"
}()
let archiveExts: Set<String> = ["7z","zip","rar","tar","gz","tgz","xz","txz","bz2","tbz","tbz2","iso","wim","cab","dmg","lzma","zst","arj","cpio","rpm","deb","jar","apk","001","z","lz","lzh","xar","pkg","vhd","vmdk","squashfs"]

func fmtSize(_ s: Int64) -> String { s < 0 ? "" : ByteCountFormatter.string(fromByteCount: s, countStyle: .file) }
func fmtExact(_ s: Int64) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal
    return (f.string(from: NSNumber(value: s)) ?? "\(s)") + L(" 字节")
}
func fmtDur(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "--:--:--" }
    let s = Int(t); return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}
let dateFmt: DateFormatter = { let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd HH:mm"; return d }()

@discardableResult
func msgBox(_ title: String, _ text: String, buttons: [String] = [L("确定")]) -> Int {
    let a = NSAlert(); a.messageText = title; a.informativeText = text
    for b in buttons { a.addButton(withTitle: b) }
    let r = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    return r
}
func confirm(_ title: String, _ text: String, ok: String = L("确定")) -> Bool { msgBox(title, text, buttons: [ok, L("取消")]) == 0 }
func ask(_ title: String, _ info: String, _ def: String, secure: Bool = false, combo: [String] = []) -> String? {
    let a = NSAlert(); a.messageText = title; a.informativeText = info
    let f: NSTextField
    if !combo.isEmpty { let c = NSComboBox(frame: NSRect(x: 0, y: 0, width: 320, height: 26)); c.addItems(withObjectValues: combo); f = c }
    else if secure { f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)) }
    else { f = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)) }
    f.stringValue = def; a.accessoryView = f
    a.addButton(withTitle: L("确定")); a.addButton(withTitle: L("取消"))
    a.window.initialFirstResponder = f
    return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
}
func askPassword(_ name: String) -> String? { ask(L("输入密码"), LF("「%@」已加密", "\(name)"), "", secure: true) }
func chooseFolder(_ msg: String, start: URL?) -> URL? {
    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
    p.canCreateDirectories = true; p.message = msg; p.prompt = L("选择"); p.directoryURL = start
    return p.runModal() == .OK ? p.url : nil
}
func isArchiveURL(_ u: URL) -> Bool {
    let n = u.lastPathComponent.lowercased()
    return archiveExts.contains(u.pathExtension.lowercased()) || n.range(of: #"\.(7z|zip|rar)\.0*1$"#, options: .regularExpression) != nil
}
func isDirPath(_ p: String) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
func treeSize(_ u: URL) -> Int64 {
    if !isDirPath(u.path) { return Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    var t: Int64 = 0
    if let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey]) {
        for case let f as URL in en { t += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    return t
}
func archiveBaseName(_ u: URL) -> String {
    let n = u.lastPathComponent
    for s in [".tar.gz", ".tar.xz", ".tar.bz2", ".7z.001", ".zip.001", ".rar.001", ".tar.zst"] where n.lowercased().hasSuffix(s) { return String(n.dropLast(s.count)) }
    if let r = n.range(of: #"\.part0*1\.rar$"#, options: [.regularExpression, .caseInsensitive]) { return String(n[..<r.lowerBound]) }
    return (n as NSString).deletingPathExtension
}

// MARK: - Preferences
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard
    @Published var showDotDot: Bool { didSet { d.set(showDotDot, forKey: "showDotDot"); AppModel.shared.panels.forEach { $0.applySort() } } }
    @Published var showHidden: Bool { didSet { d.set(showHidden, forKey: "showHidden"); AppModel.shared.refreshHidden() } }
    @Published var gridLines: Bool { didSet { d.set(gridLines, forKey: "gridLines") } }
    @Published var fullRow: Bool { didSet { d.set(fullRow, forKey: "fullRow") } }
    @Published var workDir: String { didSet { d.set(workDir, forKey: "workDir") } }
    @Published var viewMode: String { didSet { d.set(viewMode, forKey: "viewMode") } }
    @Published var dual: Bool { didSet { d.set(dual, forKey: "dual") } }
    init() {
        showDotDot = d.object(forKey: "showDotDot") as? Bool ?? true
        showHidden = d.bool(forKey: "showHidden")
        gridLines = d.object(forKey: "gridLines") as? Bool ?? false
        fullRow = d.object(forKey: "fullRow") as? Bool ?? true
        workDir = d.string(forKey: "workDir") ?? ""
        viewMode = d.string(forKey: "viewMode") ?? "details"
        dual = d.bool(forKey: "dual")
    }
    func tempDir() -> URL {
        let base = workDir.isEmpty ? FileManager.default.temporaryDirectory : URL(fileURLWithPath: workDir)
        let u = base.appendingPathComponent("7zip-gui").appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

// MARK: - Entries
struct Entry: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDir: Bool
    var isParent = false
    var size: Int64 = -1
    var packed: Int64 = -1
    var modified = ""
    var created = ""
    var attrs = ""
    var crc = ""
    var method = ""
    var encrypted = ""
    var comment = ""
    var typeKey: String { isDir ? "" : (name as NSString).pathExtension.lowercased() }
}

struct ArcItem { var path: String; var isDir: Bool; var size: Int64; var packed: Int64; var modified: String; var created: String; var attrs: String; var crc: String; var method: String; var encrypted: String; var comment: String }

func parseSLT(_ s: String) -> (items: [ArcItem], header: [String: String]) {
    var items: [ArcItem] = []; var header: [String: String] = [:]
    let sep = s.range(of: "\n----------\n")
    let headPart = sep.map { String(s[..<$0.lowerBound]) } ?? s
    for line in headPart.split(separator: "\n") {
        if let eq = line.range(of: " = ") { header[String(line[..<eq.lowerBound])] = String(line[eq.upperBound...]) }
    }
    guard let r = sep else { return ([], header) }
    for block in s[r.upperBound...].components(separatedBy: "\n\n") {
        var f: [String: String] = [:]
        for line in block.split(separator: "\n") {
            if let eq = line.range(of: " = ") { f[String(line[..<eq.lowerBound])] = String(line[eq.upperBound...]) }
            else if line.hasSuffix(" =") { f[String(line.dropLast(2))] = "" }
        }
        guard let p = f["Path"], !p.isEmpty else { continue }
        let dir = f["Folder"] == "+" || (f["Attributes"]?.hasPrefix("D") ?? false)
        items.append(ArcItem(path: p, isDir: dir, size: f["Size"].flatMap { Int64($0) } ?? -1,
                             packed: f["Packed Size"].flatMap { Int64($0) } ?? -1,
                             modified: String((f["Modified"] ?? "").prefix(16)), created: String((f["Created"] ?? "").prefix(16)),
                             attrs: f["Attributes"] ?? "", crc: f["CRC"] ?? "", method: f["Method"] ?? "",
                             encrypted: f["Encrypted"] == "+" ? "+" : (f["Encrypted"] == "-" ? "-" : ""), comment: f["Comment"] ?? ""))
    }
    return (items, header)
}

// MARK: - Runner (7zz with progress)
final class Runner: ObservableObject {
    @Published var running = false
    @Published var paused = false
    @Published var percent: Double = 0
    @Published var title = ""
    @Published var current = ""
    @Published var files = 0
    var start = Date()
    var pausedAt: Date? = nil
    var pausedTotal: TimeInterval = 0
    var total: Int64 = 0
    var ratioPath: String?
    var proc: Process?
    var cancelled = false
    var window: NSWindow?
    var lastProgAt: CFAbsoluteTime = 0
    var callCount = 1
    var callIndex = 0
    private var combined = ""
    private var queue: [ToolCall] = []

    static func launchSync(_ call: ToolCall, cwd: URL?) -> (Int32, String) {
        if !FileManager.default.isExecutableFile(atPath: call.executable) {
            if call.executable == UNRAR { return (-1, unrarMissingText()) }
            return (-1, "Cannot run \(call.executable)")
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: call.executable); p.arguments = call.arguments
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "\(error)") }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: d, as: UTF8.self)
        return call.executable == UNRAR ? annotateUnrarResult(p.terminationStatus, text) : (p.terminationStatus, text)
    }

    static func runSync(_ args: [String], cwd: URL? = nil) -> (Int32, String) {
        if ["x","e","a","u","d","rn"].contains(args.first ?? "") { Access.ensure(args: args, cwd: cwd) }
        var all = ""
        for call in planToolCalls(args, progress: false) {
            let snap = rootSnapshot(call.elimRoot)
            let (code, out) = launchSync(call, cwd: cwd)
            if code == 0, let dest = call.elimRoot { eliminateSingleRoot(dest, previous: snap) }
            all += out
            if code != 0 { return (code, all) }
        }
        return (0, all)
    }

    var elapsed: TimeInterval { Date().timeIntervalSince(start) - pausedTotal - (pausedAt.map { Date().timeIntervalSince($0) } ?? 0) }

    func run(title: String, args: [String], cwd: URL? = nil, total: Int64 = 0, ratioPath: String? = nil, done: @escaping (Int32, String) -> Void) {
        if running { msgBox(L("请稍候"), L("已有任务正在进行。")); return }
        if ["x","e","a","u","d","rn"].contains(args.first ?? "") { Access.ensure(args: args, cwd: cwd) }
        self.title = title; percent = 0; current = ""; files = 0; running = true; cancelled = false; paused = false
        start = Date(); pausedAt = nil; pausedTotal = 0; self.total = total; self.ratioPath = ratioPath
        queue = planToolCalls(args, progress: true)
        callCount = max(queue.count, 1); callIndex = 0; combined = ""
        showWindow()
        startCall(0, cwd: cwd, done: done)
    }

    private func startCall(_ index: Int, cwd: URL?, done: @escaping (Int32, String) -> Void) {
        guard index < queue.count else { finish(0, done: done); return }
        let call = queue[index]
        callIndex = index
        if !FileManager.default.isExecutableFile(atPath: call.executable) {
            combined += call.executable == UNRAR ? unrarMissingText() : "Cannot run \(call.executable)\n"
            finish(-1, done: done)
            return
        }
        let snap = rootSnapshot(call.elimRoot)
        let p = Process(); p.executableURL = URL(fileURLWithPath: call.executable); p.arguments = call.arguments
        if let cwd { p.currentDirectoryURL = cwd }
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
        var all = ""; let lock = NSLock()
        let re = try! NSRegularExpression(pattern: #"^(\d+)%(?:\s+(\d+))?(?:\s+[-+U=R.]\s+(.*))?"#)
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData; if d.isEmpty { return }
            let s = String(decoding: d, as: UTF8.self)
            lock.lock(); all += s; lock.unlock()
            let parts = s.split(whereSeparator: { $0 == "\u{8}" || $0 == "\r" || $0 == "\n" })
            var n: Double?; var fc: Int?; var file = ""
            for part in parts {
                let t = part.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                if let f = unrarActivityPath(t) { file = f }
                let ns = t as NSString
                if let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
                    n = Double(ns.substring(with: m.range(at: 1))) ?? n
                    if m.range(at: 2).location != NSNotFound { fc = Int(ns.substring(with: m.range(at: 2))) }
                    if m.range(at: 3).location != NSNotFound {
                        let f = ns.substring(with: m.range(at: 3))
                        if !f.isEmpty { file = f }
                    }
                }
            }
            guard n != nil || !file.isEmpty else { return }
            let shown = n ?? 0
            let now = CFAbsoluteTimeGetCurrent()
            if shown < 100, now - (self?.lastProgAt ?? 0) < 0.08, file.isEmpty { return }
            self?.lastProgAt = now
            let count = self?.callCount ?? 1
            let idx = self?.callIndex ?? 0
            let span = 100.0 / Double(max(count, 1))
            let overall = Double(idx) * span + shown / 100.0 * span
            DispatchQueue.main.async {
                if n != nil { self?.percent = overall }
                if let fc { self?.files = fc }
                if !file.isEmpty { self?.current = file }
            }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData; if d.isEmpty { return }
            lock.lock(); all += String(decoding: d, as: UTF8.self); lock.unlock()
        }
        p.terminationHandler = { [weak self] pr in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let rest = String(decoding: (try? out.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
                + String(decoding: (try? err.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
            lock.lock(); all += rest; var text = all; var code = pr.terminationStatus; lock.unlock()
            if call.executable == UNRAR { (code, text) = annotateUnrarResult(code, text) }
            if code == 0, let dest = call.elimRoot { eliminateSingleRoot(dest, previous: snap) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.combined += text
                if !self.combined.hasSuffix("\n") { self.combined += "\n" }
                if self.cancelled { self.finish(-2, done: done); return }
                if code != 0 { self.finish(code, done: done); return }
                if index + 1 < self.queue.count { self.startCall(index + 1, cwd: cwd, done: done); return }
                self.finish(0, done: done)
            }
        }
        do { try p.run(); proc = p } catch {
            combined += "\(error)\n"
            finish(-1, done: done)
        }
    }

    private func finish(_ code: Int32, done: (Int32, String) -> Void) {
        running = false; proc = nil; paused = false
        window?.orderOut(nil)
        done(code, combined)
    }
    func showWindow() {
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 280), styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: ProgressPanel(r: self))
            w.isReleasedWhenClosed = false; w.level = .floating
            window = w
        }
        window?.title = title
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
    func background() { window?.orderOut(nil) }
    func cancel() {
        cancelled = true
        if paused, let p = proc { kill(p.processIdentifier, SIGCONT) }
        proc?.terminate()
    }
    func togglePause() {
        guard let p = proc else { return }
        if paused { kill(p.processIdentifier, SIGCONT); if let a = pausedAt { pausedTotal += Date().timeIntervalSince(a) }; pausedAt = nil }
        else { kill(p.processIdentifier, SIGSTOP); pausedAt = Date() }
        paused.toggle()
    }
}

struct ProgressPanel: View {
    @ObservedObject var r: Runner
    func ratioText(_ done: Int64) -> String {
        guard let rp = r.ratioPath, done > 0 else { return "—" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: rp)
        guard let n = attrs?[.size] as? NSNumber else { return "—" }
        return "\(Int(n.doubleValue * 100 / Double(done)))%"
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let el = r.elapsed
            let done = Int64(Double(r.total) * r.percent / 100)
            let speed = el > 0 ? Double(done) / el : 0
            let remain = r.percent > 0 ? el * (100 - r.percent) / r.percent : .infinity
            let ratio = ratioText(done)
            VStack(alignment: .leading, spacing: 8) {
                Text(r.title).font(.headline).lineLimit(1)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text(L("已用时间：")).foregroundColor(.secondary); Text(fmtDur(el)); Text(L("总大小：")).foregroundColor(.secondary); Text(r.total > 0 ? fmtSize(r.total) : "—") }
                    GridRow { Text(L("剩余时间：")).foregroundColor(.secondary); Text(fmtDur(remain)); Text(L("速度：")).foregroundColor(.secondary); Text(r.total > 0 ? fmtSize(Int64(speed)) + "/s" : "—") }
                    GridRow { Text(L("文件：")).foregroundColor(.secondary); Text("\(r.files)"); Text(L("已处理：")).foregroundColor(.secondary); Text(r.total > 0 ? fmtSize(done) : "—") }
                    GridRow { Text(""); Text(""); Text(L("压缩率：")).foregroundColor(.secondary); Text(ratio) }
                }.font(.callout)
                Text(r.current).lineLimit(1).truncationMode(.middle).font(.caption)
                ProgressView(value: r.percent, total: 100)
                HStack {
                    Text("\(Int(r.percent))%\(r.paused ? L("（已暂停）") : "")")
                    Spacer()
                    Button(L("后台")) { r.background() }
                    Button(r.paused ? L("继续") : L("暂停")) { r.togglePause() }
                    Button(L("取消")) { r.cancel() }.keyboardShortcut(.cancelAction)
                }
            }.padding().frame(width: 480)
        }
    }
}

// MARK: - Streaming text job (hash / benchmark)
final class StreamJob: ObservableObject {
    @Published var text = ""
    @Published var running = false
    var proc: Process?
    private var buf = ""
    private var pending = false
    private var flushGen = 0
    func run(_ args: [String], cwd: URL? = nil) {
        stop(); text = ""; buf = ""; pending = false; running = true
        let p = Process(); p.executableURL = URL(fileURLWithPath: SEVENZ); p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData; if d.isEmpty { return }
            let s = String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\u{8}", with: "")
            DispatchQueue.main.async { self?.enqueue(s) }
        }
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.flushText(); self?.running = false }
        }
        do { try p.run(); proc = p } catch { text = "\(error)"; running = false }
    }
    private func enqueue(_ s: String) {
        buf += s
        guard !pending else { return }
        pending = true
        flushGen += 1
        let n = flushGen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, n == self.flushGen else { return }
            self.flushText()
        }
    }
    private func flushText() {
        pending = false
        if !buf.isEmpty { text += buf; buf = "" }
    }
    func stop() { proc?.terminate(); proc = nil; flushText() }
}

struct TextWindowView: View {
    let text: String
    var body: some View {
        VStack(alignment: .trailing) {
            ScrollView { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                .background(Color(nsColor: .textBackgroundColor))
            Button(L("复制全部")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        }.padding().frame(minWidth: 560, minHeight: 300)
    }
}
struct HashView: View {
    @ObservedObject var job: StreamJob
    var body: some View { VStack { if job.running { ProgressView(L("正在计算…")).padding(.top) }; TextWindowView(text: job.text) } }
}
var openWindows: [NSWindow] = []
func showWindow<V: View>(_ title: String, _ view: V, size: NSSize = NSSize(width: 640, height: 420)) {
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    w.title = title; w.contentView = NSHostingView(rootView: view); w.isReleasedWhenClosed = false
    w.center(); w.makeKeyAndOrderFront(nil)
    openWindows.append(w)
    openWindows.removeAll { !$0.isVisible && $0 !== w }
}
func showText(_ title: String, _ text: String) { showWindow(title, TextWindowView(text: text)) }
