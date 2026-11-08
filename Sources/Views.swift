import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum IconStore {
    static let folder = NSWorkspace.shared.icon(for: .folder)
    static let parent = NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: nil) ?? NSImage()
    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        return c
    }()
}

func entryIcon(_ e: Entry, inArchive: Bool) -> NSImage {
    if e.isParent { return IconStore.parent }
    if e.isDir { return IconStore.folder }
    let key = inArchive ? "ext:\(e.typeKey)" as NSString : e.path as NSString
    if let hit = IconStore.cache.object(forKey: key) { return hit }
    let img = inArchive
        ? NSWorkspace.shared.icon(for: UTType(filenameExtension: e.typeKey) ?? .data)
        : NSWorkspace.shared.icon(forFile: e.path)
    IconStore.cache.setObject(img, forKey: key)
    return img
}

struct BackgroundJobButton: View {
    @ObservedObject var r = AppModel.shared.runner
    var body: some View {
        if r.running {
            Button { r.showWindow() } label: { Label(LF("后台任务 %@%", "\(Int(r.percent))"), systemImage: "hourglass") }
        }
    }
}

struct ContentView: View {
    @ObservedObject var app = AppModel.shared
    @ObservedObject var prefs = Prefs.shared

    func tb(_ title: String, _ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { VStack(spacing: 2) { Image(systemName: icon).font(.title2); Text(title).font(.caption) }.frame(width: 52) }
            .buttonStyle(.borderless)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tb(L("添加"), "plus.rectangle.on.folder") { app.showAdd() }
                tb(L("解压"), "arrow.down.doc") { app.showExtract() }
                tb(L("测试"), "checkmark.seal") { app.test() }
                Divider().frame(height: 36)
                tb(L("复制"), "doc.on.doc") { app.copyMove(move: false) }
                tb(L("移动"), "arrow.right.doc.on.clipboard") { app.copyMove(move: true) }
                tb(L("删除"), "xmark.bin") { app.delete() }
                tb(L("信息"), "info.circle") { app.properties() }
                Spacer()
                BackgroundJobButton()
            }.padding(8)
            Divider()
            if app.panels.count == 2 {
                if prefs.dual {
                    HSplitView { PaneView(p: app.panels[0]); PaneView(p: app.panels[1]) }
                } else { PaneView(p: app.panels[0]) }
            }
            StatusBar(p: app.cur)
        }
        .sheet(item: $app.addReq) { AddView(req: $0) }
        .sheet(item: $app.extractReq) { ExtractView(req: $0) }
        .frame(minWidth: 760, minHeight: 460)
        .background(WindowAccessor())
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.identifier = NSUserInterfaceItemIdentifier("main-dipper"); v.window?.setFrameAutosaveName("DipperMain") }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct StatusBar: View {
    @ObservedObject var p: Panel
    var body: some View {
        let sel = p.selected
        let selSize = sel.reduce(Int64(0)) { $0 + max(0, $1.size) }
        let all = p.entries.filter { !$0.isParent }
        let total = all.reduce(Int64(0)) { $0 + max(0, $1.size) }
        HStack(spacing: 18) {
            Text(LF("选定 %@ / %@ 个项目", "\(sel.count)", "\(all.count)"))
            Text(sel.isEmpty ? LF("总计 %@", "\(fmtSize(total))") : LF("选定大小 %@", "\(fmtSize(selSize))"))
            if let f = sel.first, sel.count == 1 { Text(LF("修改时间 %@", "\(f.modified)")) }
            Spacer()
            if p.archive != nil { Text(p.archiveHeader["Type"].map { LF("格式：%@", "\($0)") } ?? "") }
        }.font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
    }
}

struct PaneView: View {
    @ObservedObject var p: Panel
    @ObservedObject var app = AppModel.shared
    @ObservedObject var prefs = Prefs.shared
    @State var targeted = false
    var isActive: Bool { !prefs.dual || app.active == p.idx }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { p.up() } label: { Image(systemName: "arrow.up") }.help(L("上一级 (⌫)"))
                Menu {
                    ForEach(app.history.prefix(20), id: \.self) { h in Button(h) { p.go(h) } }
                } label: { Image(systemName: "clock.arrow.circlepath") }.frame(width: 40).help(L("文件夹历史"))
                TextField(L("地址"), text: $p.address).textFieldStyle(.roundedBorder).onSubmit { p.go(p.address) }
            }.padding(6)
            content
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    var urls: [URL] = []; let g = DispatchGroup(); let lock = NSLock()
                    for pr in providers {
                        g.enter()
                        _ = pr.loadObject(ofClass: URL.self) { u, _ in if let u { lock.lock(); urls.append(u); lock.unlock() }; g.leave() }
                    }
                    g.notify(queue: .main) { app.handleDrop(urls, on: p) }
                    return true
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(targeted ? Color.accentColor : (prefs.dual && isActive ? Color.accentColor.opacity(0.5) : .clear), lineWidth: 2))
        .simultaneousGesture(TapGesture().onEnded { if app.active != p.idx { app.active = p.idx } })
        .onChange(of: p.selection) { _, _ in if prefs.dual && app.active != p.idx && !p.selection.isEmpty { app.active = p.idx } }
        .frame(minWidth: 300)
    }

    @ViewBuilder var content: some View {
        switch prefs.viewMode {
        case "large": IconGrid(p: p, size: 48, minW: 100)
        case "small": IconGrid(p: p, size: 16, minW: 180)
        case "list": ListMode(p: p)
        default: DetailsTable(p: p)
        }
    }
}

func entryMenu(_ p: Panel) -> some View {
    let app = AppModel.shared
    return Group {
        Button(L("打开")) { app.openSelected() }
        Button(L("在内部打开")) { app.openInside() }
        Button(L("在外部打开")) { app.openOutside() }
        Divider()
        Button(L("解压…")) { app.showExtract() }
        Button(L("测试")) { app.test() }
        Button(L("添加到压缩包…")) { app.showAdd() }.disabled(p.archive != nil)
        Divider()
        Button(L("重命名")) { app.rename() }
        Button(L("复制到…")) { app.copyMove(move: false, toPicked: true) }
        Button(L("移动到…")) { app.copyMove(move: true, toPicked: true) }
        Button(L("删除")) { app.delete() }
        Divider()
        Menu("CRC SHA") { ForEach(["CRC32", "CRC64", "SHA1", "SHA256", "BLAKE2sp", "*"], id: \.self) { m in Button(m == "*" ? L("*（全部）") : m) { app.hash(m) } } }
        Button(L("属性")) { app.properties() }
    }
}

struct DetailsTable: View {
    @ObservedObject var p: Panel
    @ObservedObject var prefs = Prefs.shared
    @State var cust = TableColumnCustomization<Entry>()
    @State var loaded = false
    @State var colSave = 0

    var table: some View {
        Table(of: Entry.self, selection: $p.selection, sortOrder: $p.sortOrder, columnCustomization: $cust) {
            TableColumn(L("名称"), value: \Entry.name, comparator: .localizedStandard) { e in
                HStack(spacing: 4) { Image(nsImage: entryIcon(e, inArchive: p.archive != nil)).resizable().frame(width: 16, height: 16); Text(e.name) }
            }.width(min: 160, ideal: 300).customizationID("name").disabledCustomizationBehavior(.visibility)
            TableColumn(L("大小"), value: \Entry.size) { e in Text(fmtSize(e.size)).frame(maxWidth: .infinity, alignment: .trailing) }.width(80).customizationID("size")
            TableColumn(L("压缩后大小"), value: \Entry.packed) { e in Text(fmtSize(e.packed)).frame(maxWidth: .infinity, alignment: .trailing) }.width(80).customizationID("packed")
            TableColumn(L("修改时间"), value: \Entry.modified) { e in Text(e.modified) }.width(125).customizationID("mtime")
            TableColumn(L("创建时间"), value: \Entry.created) { e in Text(e.created) }.width(125).customizationID("ctime").defaultVisibility(.hidden)
            TableColumn(L("属性"), value: \Entry.attrs) { e in Text(e.attrs) }.width(70).customizationID("attrs").defaultVisibility(.hidden)
            TableColumn("CRC", value: \Entry.crc) { e in Text(e.crc).font(.system(.body, design: .monospaced)) }.width(80).customizationID("crc")
            TableColumn(L("方法"), value: \Entry.method) { e in Text(e.method) }.width(90).customizationID("method")
            TableColumn(L("加密"), value: \Entry.encrypted) { e in Text(e.encrypted) }.width(40).customizationID("enc")
            TableColumn(L("注释"), value: \Entry.comment) { e in Text(e.comment) }.width(100).customizationID("comment").defaultVisibility(.hidden)
        } rows: {
            ForEach(p.entries) { e in
                TableRow(e).itemProvider { provider(e) }
            }
        }
        .contextMenu(forSelectionType: String.self) { _ in entryMenu(p) } primaryAction: { ids in
            if let id = ids.first, let e = p.entries.first(where: { $0.id == id }) { p.enter(e) }
        }
    }
    func provider(_ e: Entry) -> NSItemProvider? {
        guard let u = AppModel.shared.dragURL(p, e) else { return nil }
        return NSItemProvider(object: u as NSURL)
    }
    var body: some View {
        Group {
            if prefs.gridLines { table.tableStyle(.bordered(alternatesRowBackgrounds: true)) }
            else { table.tableStyle(.inset(alternatesRowBackgrounds: false)) }
        }
        .onAppear {
            if !loaded, let d = UserDefaults.standard.data(forKey: "cols\(p.idx)"), let c = try? JSONDecoder().decode(TableColumnCustomization<Entry>.self, from: d) { cust = c }
            loaded = true
        }
        .onChange(of: cust) { _, c in
            guard loaded else { return }
            colSave += 1
            let n = colSave
            let idx = p.idx
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard n == colSave, let d = try? JSONEncoder().encode(c) else { return }
                UserDefaults.standard.set(d, forKey: "cols\(idx)")
            }
        }
    }
}

struct ListMode: View {
    @ObservedObject var p: Panel
    var body: some View {
        List(p.entries, selection: $p.selection) { e in
            HStack { Image(nsImage: entryIcon(e, inArchive: p.archive != nil)).resizable().frame(width: 16, height: 16); Text(e.name) }
                .onDrag { AppModel.shared.dragURL(p, e).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider() }
        }
        .contextMenu(forSelectionType: String.self) { _ in entryMenu(p) } primaryAction: { ids in
            if let id = ids.first, let e = p.entries.first(where: { $0.id == id }) { p.enter(e) }
        }
    }
}

struct IconGrid: View {
    @ObservedObject var p: Panel
    let size: CGFloat
    let minW: CGFloat
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minW), alignment: .leading)], spacing: 6) {
                ForEach(p.entries) { e in
                    let sel = p.selection.contains(e.id)
                    Group {
                        if size > 20 {
                            VStack { Image(nsImage: entryIcon(e, inArchive: p.archive != nil)).resizable().frame(width: size, height: size)
                                Text(e.name).font(.caption).lineLimit(2).multilineTextAlignment(.center) }.frame(width: minW - 8)
                        } else {
                            HStack { Image(nsImage: entryIcon(e, inArchive: p.archive != nil)).resizable().frame(width: size, height: size); Text(e.name).lineLimit(1) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(sel ? Color.accentColor.opacity(0.3) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { p.enter(e) }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) { if sel { p.selection.remove(e.id) } else { p.selection.insert(e.id) } }
                        else { p.selection = [e.id] }
                    }
                    .onDrag { AppModel.shared.dragURL(p, e).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider() }
                    .contextMenu { entryMenu(p) }
                }
            }.padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Options
struct OptionsView: View {
    @ObservedObject var prefs = Prefs.shared
    var body: some View {
        TabView {
            AssocView().tabItem { Text(L("系统")) }
            ServicesInfo().tabItem { Text(L("iDipper")) }
            Form {
                Toggle(L("显示「..」项"), isOn: $prefs.showDotDot)
                Toggle(L("显示隐藏文件"), isOn: $prefs.showHidden)
                Toggle(L("整行选择"), isOn: $prefs.fullRow).disabled(true)
                Text(L("（macOS 表格始终整行选择）")).font(.caption).foregroundColor(.secondary)
                Toggle(L("显示网格线"), isOn: $prefs.gridLines)
            }.padding().tabItem { Text(L("文件管理器")) }
            Form {
                Picker(L("工作文件夹："), selection: Binding(get: { prefs.workDir.isEmpty ? 0 : 1 }, set: { if $0 == 0 { prefs.workDir = "" } else if prefs.workDir.isEmpty { prefs.workDir = chooseFolder(L("选择工作文件夹"), start: nil)?.path ?? "" } })) {
                    Text(L("系统临时文件夹")).tag(0); Text(L("指定位置")).tag(1)
                }.pickerStyle(.radioGroup)
                HStack { Text(prefs.workDir.isEmpty ? FileManager.default.temporaryDirectory.path : prefs.workDir).font(.caption).foregroundColor(.secondary)
                    Button("…") { if let u = chooseFolder(L("选择工作文件夹"), start: nil) { prefs.workDir = u.path } } }
                Text(L("用于从压缩包中拖出或打开文件时的临时解压。")).font(.caption).foregroundColor(.secondary)
            }.padding().tabItem { Text(L("文件夹")) }
            LanguagePane().tabItem { Text(L("语言")) }
        }.padding().frame(width: 560, height: 460)
    }
}

let assocExts = ["7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "xz", "txz", "iso", "wim", "cab", "lzma", "zst", "001", "arj", "cpio", "rpm", "deb", "z", "lzh"]
struct AssocView: View {
    @State var state: [String: Bool] = [:]
    @State var msg = ""
    var me: URL { Bundle.main.bundleURL }
    func current(_ e: String) -> Bool {
        guard let t = UTType(filenameExtension: e), let u = NSWorkspace.shared.urlForApplication(toOpen: t) else { return false }
        return u.standardizedFileURL.path == me.standardizedFileURL.path
    }
    func set(_ e: String, _ on: Bool) {
        guard let t = UTType(filenameExtension: e) else { return }
        let target = on ? me : URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")
        NSWorkspace.shared.setDefaultApplication(at: target, toOpen: t) { err in
            DispatchQueue.main.async {
                if let err { msg = LF(".%@：%@", "\(e)", "\(err.localizedDescription)") }
                state[e] = current(e)
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text(L("用 iDipper 打开以下类型的文件（双击打开）："))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)]) {
                    ForEach(assocExts, id: \.self) { e in
                        Toggle("." + e, isOn: Binding(get: { state[e] ?? false }, set: { state[e] = $0; set(e, $0) }))
                    }
                }
            }
            HStack {
                Button(L("全部选中")) { assocExts.forEach { state[$0] = true; set($0, true) } }
                Button(L("全部取消")) { assocExts.forEach { state[$0] = false; set($0, false) } }
                Button(L("刷新")) { assocExts.forEach { state[$0] = current($0) } }
            }
            Text(msg).font(.caption).foregroundColor(.red)
            Text(L("取消关联会把该类型交还给系统「归档实用工具」。macOS 可能会弹窗请你确认。")).font(.caption).foregroundColor(.secondary)
        }.padding()
        .onAppear { assocExts.forEach { state[$0] = current($0) } }
    }
}

struct ServicesInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Finder 右键菜单（快速操作 / 服务）")).font(.headline)
            Text(L("在 Finder 中右键文件 → 「快速操作」或「服务」可看到："))
            ForEach([L("iDipper：添加到压缩包…"), L("iDipper：压缩为 .7z"), L("iDipper：压缩为 .zip"), L("iDipper：解压到当前位置"), L("iDipper：解压到同名文件夹"), L("iDipper：CRC SHA 校验")], id: \.self) { Text("• " + $0) }
            Text(L("如果看不到：打开「系统设置 → 键盘 → 键盘快捷键 → 服务 → 文件和文件夹」，勾选上面这些「iDipper」项目。")).font(.callout)
            HStack {
                Button(L("打开键盘快捷键设置")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
                Button(L("刷新服务菜单")) { NSUpdateDynamicServices() }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Benchmark
struct BenchmarkView: View {
    @StateObject var job = StreamJob()
    @State var threads = ProcessInfo.processInfo.activeProcessorCount
    @State var dict = 25
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker(L("字典大小："), selection: $dict) { ForEach(22...28, id: \.self) { Text(fmtSize(Int64(1) << $0)).tag($0) } }.frame(width: 200)
                Picker(L("CPU 线程数："), selection: $threads) { ForEach(1...ProcessInfo.processInfo.activeProcessorCount * 2, id: \.self) { Text("\($0)").tag($0) } }.frame(width: 160)
                Spacer()
                Button(L("重新开始")) { job.run(["b", "-mmt\(threads)", "-md\(dict)"]) }
                Button(L("停止")) { job.stop() }.disabled(!job.running)
            }
            if job.running { ProgressView().controlSize(.small) }
            ScrollView { Text(job.text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .background(Color(nsColor: .textBackgroundColor))
            Text(L("Rating（MIPS）越高越好。")).font(.caption).foregroundColor(.secondary)
        }.padding().frame(minWidth: 700, minHeight: 420)
        .onAppear { job.run(["b", "-mmt\(threads)", "-md\(dict)"]) }
        .onDisappear { job.stop() }
    }
}

let appLanguages: [(String, String)] = [("en", "English"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"), ("pt-BR", "Português (Brasil)"), ("it", "Italiano"), ("ru", "Русский")]
struct LanguagePane: View {
    @State var sel: String = ((UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first) ?? "system"
    var body: some View {
        Form {
            Picker(L("语言："), selection: $sel) {
                Text(L("跟随系统")).tag("system")
                Divider()
                ForEach(appLanguages, id: \.0) { Text($0.1).tag($0.0) }
            }
            .onChange(of: sel) { _, v in applyLanguage(v) }
            Text(L("更改语言后需要重新启动应用。")).font(.caption).foregroundColor(.secondary)
        }.padding()
    }
}
func applyLanguage(_ code: String) {
    if code == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
    else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
    UserDefaults.standard.synchronize()
    if confirm(L("需要重新启动"), L("新的语言将在重新启动后生效。现在重新启动吗？"), ok: L("立即重新启动")) {
        let path = Bundle.main.bundlePath
        let cfg = NSWorkspace.OpenConfiguration(); cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg) { _, _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
    }
}
