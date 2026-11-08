import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pending: [URL] = []
    static var ready = false
    var monitor: Any?
    func applicationWillFinishLaunching(_ notification: Notification) {
        Access.restore()
        AppModel.shared.setup()
        NSApp.servicesProvider = self
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSUpdateDynamicServices()
        AppDelegate.ready = true
        if !AppDelegate.pending.isEmpty { let p = AppDelegate.pending; AppDelegate.pending = []; DispatchQueue.main.async { AppModel.shared.openURLs(p) } }
        let args: [String] = {
            var out: [String] = []; var skip = false
            for a in CommandLine.arguments.dropFirst() {
                if skip { skip = false; continue }
                if a.hasPrefix("-") { skip = true; continue }   // "-key value" = UserDefaults argument
                if FileManager.default.fileExists(atPath: a) { out.append(a) }
            }
            return out
        }()
        if !args.isEmpty { DispatchQueue.main.async { AppModel.shared.openURLs(args.map { URL(fileURLWithPath: $0) }) } }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in self.handleKey(e) ? nil : e }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if AppDelegate.ready { AppModel.shared.openURLs(urls) } else { AppDelegate.pending += urls }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        let base = (Prefs.shared.workDir.isEmpty ? FileManager.default.temporaryDirectory : URL(fileURLWithPath: Prefs.shared.workDir)).appendingPathComponent("7zip-gui")
        try? FileManager.default.removeItem(at: base)
    }

    func handleKey(_ e: NSEvent) -> Bool {
        guard let w = NSApp.keyWindow, w.identifier?.rawValue == "main-dipper", w.attachedSheet == nil else { return false }
        if w.firstResponder is NSText { return false }   // editing address bar
        let app = AppModel.shared
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = f.subtracting([.function, .numericPad]).isEmpty
        let opt = f.contains(.option), shift = f.contains(.shift), cmd = f.contains(.command)
        let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        if opt, !cmd, let n = digits[e.keyCode] { if shift { app.setBookmark(n) } else { app.gotoBookmark(n) }; return true }
        switch e.keyCode {
        case 120 where plain: app.rename()
        case 96 where plain: app.copyMove(move: false)
        case 97 where plain: app.copyMove(move: true)
        case 98 where plain: app.newItem(folder: true)
        case 101 where plain: app.toggleDual()
        case 111 where opt: showHistory()
        case 48 where plain: app.switchPane()
        case 51 where plain: app.cur.up()
        case 51 where cmd: app.delete()
        case 117: app.delete()
        case 36 where opt: app.properties()
        case 36 where plain: app.openSelected()
        case 76 where plain: app.openSelected()
        default: return false
        }
        return true
    }
    func showHistory() {
        let h = AppModel.shared.history
        guard !h.isEmpty else { return }
        let a = NSAlert(); a.messageText = L("文件夹历史")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 460, height: 26)); pop.addItems(withTitles: h); a.accessoryView = pop
        a.addButton(withTitle: L("打开")); a.addButton(withTitle: L("取消"))
        if a.runModal() == .alertFirstButtonReturn, let s = pop.titleOfSelectedItem { AppModel.shared.cur.go(s) }
    }

    // MARK: Finder services
    func urls(_ pb: NSPasteboard) -> [URL] { (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? [] }
    @objc func svcAdd(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let u = urls(pb); guard !u.isEmpty else { return }; AppModel.shared.cur.setDir(u[0].deletingLastPathComponent()); AppModel.shared.showAdd(u)
    }
    @objc func svc7z(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) { AppModel.shared.quickCompress(urls(pb), ext: "7z") }
    @objc func svcZip(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) { AppModel.shared.quickCompress(urls(pb), ext: "zip") }
    @objc func svcExtractHere(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) { AppModel.shared.quickExtract(urls(pb), toSubfolder: false) }
    @objc func svcExtractTo(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) { AppModel.shared.quickExtract(urls(pb), toSubfolder: true) }
    @objc func svcHash(_ pb: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let u = urls(pb); guard let f = u.first else { return }
        bringAppToFront()
        AppModel.shared.hashFiles(u, method: "CRC32,SHA256", cwd: f.deletingLastPathComponent())
    }
}

/// Bring iDipper and its main window to the front. On macOS 14+ activation is cooperative:
/// NSApp.activate(ignoringOtherApps:) is ignored when invoked from a Finder Service while Finder
/// is frontmost. Re-opening our own bundle through LaunchServices is an allowed, sandbox-safe way
/// to request activation. The main window may also not exist yet on a cold launch, so retry.
func bringAppToFront(attempt: Int = 0) {
    NSApp.unhide(nil)
    NSApp.activate()
    if attempt == 0 && !NSApp.isActive {
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true; cfg.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in }
    }
    if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "main-dipper" }) {
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil); w.orderFrontRegardless()
    }
    if attempt < 6 && (!NSApp.isActive || NSApp.windows.first(where: { $0.identifier?.rawValue == "main-dipper" && $0.isVisible }) == nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { bringAppToFront(attempt: attempt + 1) }
    }
}

func isTextEditing() -> Bool { NSApp.keyWindow?.firstResponder is NSText }
func forward(_ sel: String) { NSApp.sendAction(Selector(sel), to: nil, from: nil) }

struct AppCommands: Commands {
    @Environment(\.openWindow) var openWindow
    var app: AppModel { AppModel.shared }
    let hashes = ["CRC32", "CRC64", "SHA1", "SHA256", "BLAKE2sp"]
    var body: some Commands {
        CommandGroup(replacing: .appInfo) { Button(L("关于 iDipper")) { showAbout() } }
        CommandGroup(replacing: .newItem) {
            Button(L("新建文件夹")) { app.newItem(folder: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button(L("新建文件")) { app.newItem(folder: false) }.keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button(L("打开")) { if isTextEditing() { forward("moveToEndOfDocument:") } else { app.openSelected() } }.keyboardShortcut(.downArrow)
            Button(L("打开压缩包…")) {
                let p = NSOpenPanel(); p.canChooseDirectories = true
                if p.runModal() == .OK, let u = p.url { app.openURLs([u]) }
            }.keyboardShortcut("o")
            Button(L("在压缩包内浏览")) { app.openInside() }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button(L("用默认应用打开")) { app.openOutside() }.keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            Divider()
            Button(L("添加到压缩包…")) { app.showAdd() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button(L("解压…")) { app.showExtract() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Button(L("测试压缩包")) { app.test() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button(L("显示简介")) { app.properties() }.keyboardShortcut("i")
            Button(L("重命名")) { app.rename() }.keyboardShortcut("r")
            Button(L("复制到…")) { app.copyMove(move: false) }.keyboardShortcut("c", modifiers: [.command, .option])
            Button(L("移动到…")) { app.copyMove(move: true) }.keyboardShortcut("v", modifiers: [.command, .option])
            Button(L("移到废纸篓")) { if isTextEditing() { forward("deleteToBeginningOfLine:") } else { app.delete() } }.keyboardShortcut(.delete)
            Divider()
            Menu(L("校验和")) {
                ForEach(hashes, id: \.self) { m in Button(m) { app.hash(m) } }
                Divider()
                Button(L("全部算法")) { app.hash("*") }
            }
            Button(L("分割文件…")) { app.splitFile() }
            Button(L("合并文件…")) { app.combineFiles() }
            Button(L("比较文件")) { app.compare() }
            Button(L("压缩包注释…")) { app.comment() }
        }
        CommandGroup(replacing: .pasteboard) {
            Button(L("剪切")) { forward("cut:") }.keyboardShortcut("x")
            Button(L("拷贝")) { if isTextEditing() { forward("copy:") } else { app.copyToPasteboard() } }.keyboardShortcut("c")
            Button(L("粘贴")) { if isTextEditing() { forward("paste:") } else { app.pasteFromPasteboard() } }.keyboardShortcut("v")
            Button(L("全选")) { if isTextEditing() { forward("selectAll:") } else { app.selectAll() } }.keyboardShortcut("a")
            Divider()
            Button(L("取消全选")) { app.selectNone() }.keyboardShortcut("a", modifiers: [.command, .option])
            Button(L("反向选择")) { app.invert() }.keyboardShortcut("i", modifiers: [.command, .option])
            Button(L("按名称选择…")) { app.selectPattern(true) }.keyboardShortcut("=")
            Button(L("按名称取消选择…")) { app.selectPattern(false) }.keyboardShortcut("-")
        }
        CommandGroup(replacing: .toolbar) {
            Button(L("为图标")) { Prefs.shared.viewMode = "large" }.keyboardShortcut("1")
            Button(L("为小图标")) { Prefs.shared.viewMode = "small" }.keyboardShortcut("2")
            Button(L("为列表")) { Prefs.shared.viewMode = "list" }.keyboardShortcut("3")
            Button(L("为详细信息")) { Prefs.shared.viewMode = "details" }.keyboardShortcut("4")
            Divider()
            Menu(L("排序方式")) {
                Button(L("名称")) { app.cur.sortBy(0) }.keyboardShortcut("1", modifiers: [.command, .control, .option])
                Button(L("种类")) { app.cur.sortBy(10) }.keyboardShortcut("2", modifiers: [.command, .control, .option])
                Button(L("修改日期")) { app.cur.sortBy(3) }.keyboardShortcut("3", modifiers: [.command, .control, .option])
                Button(L("大小")) { app.cur.sortBy(1) }.keyboardShortcut("4", modifiers: [.command, .control, .option])
            }
            Divider()
            Button(Prefs.shared.dual ? L("隐藏双栏") : L("显示双栏")) { app.toggleDual() }.keyboardShortcut("s", modifiers: [.command, .option])
            Button(Prefs.shared.showHidden ? L("隐藏隐藏文件") : L("显示隐藏文件")) { Prefs.shared.showHidden.toggle() }.keyboardShortcut(".", modifiers: [.command, .shift])
            Button(L("刷新")) { app.refreshAll(force: true) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu(L("前往")) {
            Button(L("后退")) { app.cur.goBack() }.keyboardShortcut("[")
            Button(L("前进")) { app.cur.goForward() }.keyboardShortcut("]")
            Button(L("上层文件夹")) { if isTextEditing() { forward("moveToBeginningOfDocument:") } else { app.cur.up() } }.keyboardShortcut(.upArrow)
            Divider()
            Button(L("个人")) { app.cur.setDir(realHome) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button(L("桌面")) { app.cur.setDir(realHome.appendingPathComponent("Desktop")) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button(L("下载")) { app.cur.setDir(realHome.appendingPathComponent("Downloads")) }.keyboardShortcut("l", modifiers: [.command, .option])
            Button(L("根目录")) { app.cur.setDir(URL(fileURLWithPath: "/")) }.keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Menu(L("最近使用的文件夹")) { ForEach(app.history.prefix(15), id: \.self) { h in Button(h) { app.cur.go(h) } } }
            Button(L("前往文件夹…")) { if let s = ask(L("前往文件夹"), L("输入路径："), app.cur.location) { app.cur.go(s) } }.keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Menu(L("添加到收藏夹")) { ForEach(1...9, id: \.self) { n in Button(LF("收藏位置 %@", "\(n)")) { app.setBookmark(n) } } }
            ForEach(1...9, id: \.self) { n in
                if let b = app.bookmark(n) {
                    Button(b) { app.gotoBookmark(n) }.keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .control)
                }
            }
        }
        CommandGroup(before: .windowList) {
            Button(L("性能基准测试")) { openWindow(id: "bench") }
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button(L("键盘快捷键")) { showText(L("键盘快捷键"), L("SHORTCUT_HELP")) }
        }
    }
}

@main
struct SevenZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window(L("iDipper"), id: "main") { ContentView() }
            .commands { AppCommands() }
        Window(L("性能基准测试"), id: "bench") { BenchmarkView() }
        Settings { OptionsView() }
    }
}

func showAbout() {
    let engine = Runner.runSync([]).1.split(separator: "\n").first(where: { $0.contains("Igor Pavlov") }).map(String.init) ?? "7zz"
    let unrarLine = Runner.launchSync(ToolCall(executable: UNRAR, arguments: []), cwd: nil).1
        .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "UnRAR"
    let credits = NSAttributedString(string: L("macOS 压缩/解压文件管理器") + "\n\n" + L("压缩引擎：") + "7-Zip (7zz) by Igor Pavlov, GNU LGPL\n" + engine + "\n\n7-Zip license: iDipper.app/Contents/Resources/7zip-License.txt\nSource: https://www.7-zip.org\n\nRAR：UnRAR by Alexander Roshal, freeware\n" + unrarLine + "\nUnRAR license: iDipper.app/Contents/Resources/unrar-License.txt\nhttps://www.rarlab.com/", attributes: [.font: NSFont.systemFont(ofSize: 11)])
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: L("iDipper"), .credits: credits, .applicationVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"), .version: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")])
}
