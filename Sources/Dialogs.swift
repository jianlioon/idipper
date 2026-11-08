import SwiftUI
import AppKit

// MARK: - Add dialog
struct AddView: View {
    let req: AddRequest
    @ObservedObject var app = AppModel.shared
    @Environment(\.dismiss) var dismiss
    @State var archivePath = ""
    @State var format = "7z"
    @State var level = 5
    @State var method = L("自动")
    @State var dict = L("自动")
    @State var word = L("自动")
    @State var solid = L("自动")
    @State var threads = L("自动")
    @State var volume = ""
    @State var params = ""
    @State var update = 0
    @State var pathMode = 0
    @State var deleteAfter = false
    @State var password = ""
    @State var password2 = ""
    @State var showPw = false
    @State var encMethod = "AES-256"
    @State var encryptNames = false

    let formats = ["7z", "zip", "tar", "gzip", "bzip2", "xz", "wim"]
    let levels: [(Int, String)] = [(0, L("仅存储")), (1, L("极速压缩")), (3, L("快速压缩")), (5, L("标准压缩")), (7, L("最大压缩")), (9, L("极限压缩"))]
    var ext: String { ["7z": "7z", "zip": "zip", "tar": "tar", "gzip": "gz", "bzip2": "bz2", "xz": "xz", "wim": "wim"][format]! }
    var methods: [String] {
        switch format {
        case "7z": return [L("自动"), "LZMA2", "LZMA", "PPMd", "BZip2", "Deflate", "Deflate64", "Copy"]
        case "zip": return [L("自动"), "Deflate", "Deflate64", "BZip2", "LZMA", "PPMd", "Copy"]
        case "gzip": return ["Deflate"]; case "bzip2": return ["BZip2"]; case "xz": return ["LZMA2"]
        default: return ["—"]
        }
    }
    let dicts = [L("自动"), "64k", "256k", "1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m", "512m", "1024m", "1536m"]
    let words = [L("自动"), "8", "12", "16", "24", "32", "48", "64", "96", "128", "192", "256", "273"]
    let solids = [L("自动"), L("非固实"), "1m", "16m", "64m", "256m", "1g", "4g", "16g", "64g", L("固实")]
    var threadOpts: [String] { [L("自动")] + (1...ProcessInfo.processInfo.activeProcessorCount * 2).map(String.init) }
    let volumes = ["10M", "100M", "650M - CD", "700M - CD", "4092M - FAT", "4480M - DVD", "8128M - DVD DL", "23040M - BD"]
    let updates = [L("添加并替换文件"), L("更新并添加文件"), L("只刷新已存在的文件"), L("同步压缩包内容")]
    let paths = [L("相对路径"), L("完整路径"), L("绝对路径")]
    var canEncrypt: Bool { format == "7z" || format == "zip" }
    var single: Bool { ["gzip", "bzip2", "xz"].contains(format) }

    func bytes(_ s: String) -> Double {
        let t = s.lowercased(); guard let l = t.last else { return 0 }
        let m: Double = ["k": 1024, "m": 1048576, "g": 1073741824][String(l)] ?? 1
        return (Double(m == 1 ? t : String(t.dropLast())) ?? 0) * m
    }
    var memEstimate: (Double, Double) {
        let lvTable: [Int: Double] = [0: 0, 1: 262144, 3: 4194304, 5: 16777216, 7: 33554432, 9: 67108864]
        let lv: Double = lvTable[level] ?? 16777216
        let d: Double = dict == L("自动") ? lv : bytes(dict)
        let th: Double = Double(threads == L("自动") ? ProcessInfo.processInfo.activeProcessorCount : Int(threads) ?? 1)
        let m = method == L("自动") ? (format == "zip" ? "Deflate" : "LZMA2") : method
        switch m {
        case "LZMA2", "LZMA":
            let f: Double = m == "LZMA2" ? max(1, th / 2) : 1
            let c: Double = (d * 11.5 + 6291456) * f
            return (c, d + 2097152)
        case "PPMd": return (d + 2 * 1048576, d + 2 * 1048576)
        case "BZip2": return (th * 10 * 1048576, th * 7 * 1048576)
        default: return (th * 2 * 1048576, 2 * 1048576)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("添加到压缩包")).font(.headline)
            HStack {
                Text(L("压缩包："))
                TextField("", text: $archivePath).disabled(req.existing)
                Button("…") {
                    let p = NSSavePanel(); p.nameFieldStringValue = (archivePath as NSString).lastPathComponent
                    p.directoryURL = URL(fileURLWithPath: (archivePath as NSString).deletingLastPathComponent)
                    if p.runModal() == .OK, let u = p.url { archivePath = u.path }
                }
            }
            HStack(alignment: .top, spacing: 20) {
                Form {
                    Picker(L("压缩格式："), selection: $format) { ForEach(formats, id: \.self) { Text($0) } }.disabled(req.existing)
                    Picker(L("压缩等级："), selection: $level) { ForEach(levels, id: \.0) { Text($0.1).tag($0.0) } }
                    Picker(L("压缩方法："), selection: $method) { ForEach(methods, id: \.self) { Text($0) } }.disabled(methods.count < 2)
                    Picker(L("字典大小："), selection: $dict) { ForEach(dicts, id: \.self) { Text($0.uppercased()) } }.disabled(!["7z", "xz"].contains(format))
                    Picker(L("单词大小："), selection: $word) { ForEach(words, id: \.self) { Text($0) } }.disabled(!["7z", "xz"].contains(format))
                    Picker(L("固实数据大小："), selection: $solid) { ForEach(solids, id: \.self) { Text($0.uppercased()) } }.disabled(format != "7z")
                    Picker(L("CPU 线程数："), selection: $threads) { ForEach(threadOpts, id: \.self) { Text($0) } }
                    LabeledContent(L("压缩所需内存："), value: L("约 ") + fmtSize(Int64(memEstimate.0)))
                    LabeledContent(L("解压所需内存："), value: L("约 ") + fmtSize(Int64(memEstimate.1)))
                    HStack {
                        TextField(L("分卷大小："), text: $volume, prompt: Text(L("不分卷")))
                        Menu(L("预设")) { ForEach(volumes, id: \.self) { v in Button(v) { volume = String(v.split(separator: " ")[0]) } } }.frame(width: 70)
                    }
                    TextField(L("参数："), text: $params, prompt: Text(L("如 -mf=off")))
                }.frame(width: 360)
                Form {
                    Picker(L("更新方式："), selection: $update) { ForEach(0..<4) { Text(updates[$0]).tag($0) } }
                    Picker(L("路径模式："), selection: $pathMode) { ForEach(0..<3) { Text(paths[$0]).tag($0) } }.disabled(req.names != nil)
                    Toggle(L("创建自释放程序（macOS 不支持）"), isOn: .constant(false)).disabled(true)
                    Toggle(L("压缩后删除源文件（移到废纸篓）"), isOn: $deleteAfter)
                    Section(L("加密")) {
                        if showPw { TextField(L("输入密码："), text: $password) }
                        else { SecureField(L("输入密码："), text: $password); SecureField(L("重新输入："), text: $password2) }
                        Toggle(L("显示密码"), isOn: $showPw)
                        Picker(L("加密方法："), selection: $encMethod) {
                            if format == "zip" { Text("ZipCrypto").tag("ZipCrypto") }
                            Text("AES-256").tag("AES-256")
                        }
                        Toggle(L("加密文件名"), isOn: $encryptNames).disabled(format != "7z")
                    }.disabled(!canEncrypt)
                }.frame(width: 340)
            }
            if single && (req.files.count != 1 || isDirPath(req.files[0].path)) {
                Text(L("gzip/bzip2/xz 只能压缩单个文件，请先打包成 tar。")).foregroundColor(.red)
            }
            HStack {
                Text(LF("将添加 %@ 个项目", "\(req.files.count)")).foregroundColor(.secondary)
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("确定")) { start() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding().frame(width: 760)
        .onAppear {
            format = req.format; archivePath = req.archivePath; deleteAfter = req.deleteSource
            password = req.password; password2 = req.password
        }
        .onChange(of: format) { _, _ in
            if req.existing { return }
            archivePath = ((archivePath as NSString).deletingPathExtension) + "." + ext
            method = methods[0]; if format != "zip" { encMethod = "AES-256" }
        }
    }

    func buildArgs() -> [String]? {
        if !showPw && password != password2 { msgBox(L("密码不一致"), L("两次输入的密码不同。")); return nil }
        let cmd = ["a", "u", "u", "u"][update]
        var a = req.existing ? [cmd] : [cmd, "-t" + format]
        switch update {
        case 1: a.append("-up1q0r2x1y2z1w2")
        case 2: a.append("-up1q0r0x1y2z1w2")
        case 3: a.append("-up0q0r2x1y2z1w2")
        default: break
        }
        if !["tar", "wim"].contains(format) { a.append("-mx=\(level)") }
        if method != L("自动") && methods.count > 1 { a.append(format == "zip" ? "-mm=" + method : "-m0=" + method) }
        if ["7z", "xz"].contains(format) {
            if dict != L("自动") { a.append("-md=" + dict) }
            if word != L("自动") { a.append("-mfb=" + word) }
        }
        if format == "7z" && solid != L("自动") { a.append("-ms=" + (solid == L("非固实") ? "off" : solid == L("固实") ? "on" : solid)) }
        if threads != L("自动") && !["tar", "wim"].contains(format) { a.append("-mmt=" + threads) }
        if !password.isEmpty && canEncrypt {
            a.append("-p" + password)
            if format == "zip" { a.append("-mem=" + (encMethod == "ZipCrypto" ? "ZipCrypto" : "AES256")) }
            if format == "7z" && encryptNames { a.append("-mhe=on") }
        }
        let v = volume.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { a.append("-v" + v.lowercased().replacingOccurrences(of: "b", with: "")) }
        if pathMode == 1 { a.append("-spf2") } else if pathMode == 2 { a.append("-spf") }
        if deleteAfter && req.originals.isEmpty { a.append("-sdel") }
        a += params.split(separator: " ").map(String.init)
        a.append(archivePath); a.append("--")
        a += pathMode == 0 ? (req.names ?? req.files.map { $0.lastPathComponent }) : req.files.map { $0.path }
        return a
    }

    func start() {
        guard let args = buildArgs() else { return }
        let files = req.files
        let app = self.app; let cwd = req.cwd; let ap = archivePath
        let trashAfter = deleteAfter && !req.originals.isEmpty ? req.originals : []
        dismiss()
        DispatchQueue.global(qos: .userInitiated).async {
            let total = files.reduce(0) { $0 + treeSize($1) }
            DispatchQueue.main.async {
                app.runner.run(title: LF("正在压缩 %@", "\((ap as NSString).lastPathComponent)"), args: args, cwd: cwd, total: total, ratioPath: ap) { code, out in
                    if code != 0 && code != -2 { msgBox(L("压缩出错"), String(out.suffix(1500))) }
                    if code == 0 { trashAfter.forEach { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) } }
                    app.refreshAll()
                    if code == 0 { app.cur.selection = [ap] }
                }
            }
        }
    }
}

// MARK: - Extract dialog
struct ExtractView: View {
    let req: ExtractRequest
    @ObservedObject var app = AppModel.shared
    @Environment(\.dismiss) var dismiss
    @State var dest = ""
    @State var mode = "ask"
    @State var password = ""
    @State var showPw = false
    @State var pathMode = 0
    @State var elimRoot = false
    var multi: Bool { req.archives.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LF("解压：%@", "\(multi ? LF("%@ 个压缩包", "\(req.archives.count)") : req.archives[0].lastPathComponent)")).font(.headline)
            HStack {
                Text(L("解压到："))
                TextField("", text: $dest)
                Button("…") {
                    if let u = chooseFolder(L("解压到："), start: URL(fileURLWithPath: (dest as NSString).deletingLastPathComponent)) { dest = u.path + (multi ? "/*" : "") }
                }
            }
            if multi { Text(L("「*」会替换成各压缩包的名称")).font(.caption).foregroundColor(.secondary) }
            HStack(alignment: .top, spacing: 20) {
                Form {
                    Picker(L("路径模式："), selection: $pathMode) { Text(L("完整路径")).tag(0); Text(L("无路径")).tag(1); Text(L("绝对路径")).tag(2) }
                    Toggle(L("消除重复的根文件夹"), isOn: $elimRoot)
                    Picker(L("覆盖方式："), selection: $mode) {
                        Text(L("提示覆盖")).tag("ask"); Text(L("直接覆盖")).tag("-aoa"); Text(L("跳过已有文件")).tag("-aos")
                        Text(L("自动重命名新文件")).tag("-aou"); Text(L("自动重命名已有文件")).tag("-aot")
                    }
                    if !req.items.isEmpty { Text(LF("只解压选中的 %@ 个项目", "\(req.items.count)")).foregroundColor(.secondary) }
                }.frame(width: 330)
                Form {
                    Section(L("密码")) {
                        if showPw { TextField("", text: $password) } else { SecureField("", text: $password) }
                        Toggle(L("显示密码"), isOn: $showPw)
                    }
                }.frame(width: 220)
            }
            HStack { Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("确定")) { start() }.keyboardShortcut(.defaultAction) }
        }
        .padding().frame(width: 600)
        .onAppear { dest = req.dest; password = req.password }
    }

    func conflicts(_ a: URL, _ sel: [String]) -> [String] {
        let pr = Process(); pr.executableURL = URL(fileURLWithPath: SEVENZ)
        pr.arguments = ["l", "-slt", "-ba", a.path, "-p" + password]
        let pipe = Pipe(); pr.standardOutput = pipe; pr.standardError = Pipe()
        guard (try? pr.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); pr.waitUntilExit()
        var out: [String] = []; var path: String? = nil
        for line in (String(data: data, encoding: .utf8) ?? "").components(separatedBy: "\n") {
            if line.hasPrefix("Path = ") { path = String(line.dropFirst(7)) }
            else if line.hasPrefix("Folder = "), let p = path {
                if line == "Folder = -" && (sel.isEmpty || sel.contains(where: { p == $0 || p.hasPrefix($0 + "/") })) {
                    let rel = pathMode == 0 ? p : (p as NSString).lastPathComponent
                    if FileManager.default.fileExists(atPath: (dest as NSString).appendingPathComponent(rel)) { out.append(rel) }
                }
                path = nil
            }
        }
        return out
    }

    func start() {
        let sel = req.items
        var md = mode
        var excludes: [String] = []
        if md == "ask" {
            md = "-aoa"
            if !multi && pathMode != 2 && !elimRoot {
                let c = conflicts(req.archives[0], sel)
                var all: Bool? = nil
                for rel in c {
                    if let all { if !all { excludes.append(rel) }; continue }
                    let r = msgBox(L("确认文件替换"), LF("目标文件夹已包含同名文件：\n%@\n\n是否用压缩包中的文件替换已有文件？", "\(rel)"),
                                  buttons: [L("是"), L("全是"), L("否"), L("全否"), L("自动重命名"), L("取消")])
                    switch r {
                    case 0: break
                    case 1: all = true
                    case 2: excludes.append(rel)
                    case 3: excludes.append(rel); all = false
                    case 4: md = "-aou"; all = true
                    default: return
                    }
                }
            } else if multi || pathMode == 2 || elimRoot {
                md = "-aou"
            }
        }
        var args = [pathMode == 1 ? "e" : "x"]
        if multi { args += ["-an"] + req.archives.map { "-ai!" + $0.path } } else { args.append(req.archives[0].path) }
        args += ["-o" + dest, md, "-p" + password]
        if pathMode == 2 { args.append("-spf") }
        if elimRoot { args.append("-spe") }
        if md != "-aou" { for x in excludes where pathMode == 0 { args += ["-x!" + x] } }
        if !excludes.isEmpty && pathMode == 1 { args += excludes.map { "-x!*/" + $0 } + excludes.map { "-x!" + $0 } }
        if !sel.isEmpty { args += ["-spd", "--"] + sel }
        let app = self.app; let pw = password; let d = dest; let arcs = req.archives
        let total = arcs.reduce(0) { $0 + treeSize($1) }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            app.runner.run(title: LF("正在解压 %@", "\(multi ? LF("%@ 个压缩包", "\(arcs.count)") : arcs[0].lastPathComponent)"), args: args, total: total) { code, out in
                if code == -2 { return }
                if code != 0 {
                    if out.contains("Wrong password") || out.contains("encrypted") {
                        msgBox(L("密码错误"), L("请输入正确的密码后重试。"))
                    } else { msgBox(L("解压出错"), String(out.suffix(1500))) }
                } else {
                    if !pw.isEmpty { app.cur.password = pw }
                    if !d.contains("*") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d)]) }
                }
                app.refreshAll()
            }
        }
    }
}
