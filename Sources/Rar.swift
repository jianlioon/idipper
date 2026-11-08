import Foundation

// RAR extract and test go through the bundled UnRAR utility (Alexander Roshal,
// freeware). The bundled 7zz can list RAR archives, but this build has no RAR
// decompression codec: compressed entries fail with "Unsupported Method".
// 7-Zip prints ordinary RAR5 methods as "v6:mN" (algorithm 0), so v6:m3:1M is
// normal RAR5, not a missing future codec.
//
// UnRAR source code may be used in any software to handle RAR archives without
// limitations free of charge, but cannot be used to develop RAR (WinRAR)
// compatible archiver and to re-create RAR compression algorithm, which is
// proprietary. Distribution of modified UnRAR source code in separate form or
// as a part of other software is permitted, provided that full text of this
// paragraph, starting from "UnRAR source code" words, is included in license,
// or in documentation if license is not available, and in source code comments
// of resulting package.
//
// iDipper bundles the unmodified UnRAR executable and does not create RAR
// archives. License: Contents/Resources/unrar-License.txt

/// Bundled unrar (Contents/MacOS/unrar). `DIPPER_UNRAR` overrides; Homebrew is a dev fallback.
let UNRAR: String = {
    if let env = ProcessInfo.processInfo.environment["DIPPER_UNRAR"], FileManager.default.isExecutableFile(atPath: env) { return env }
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/unrar").path
    if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
    let brew = "/opt/homebrew/bin/unrar"
    if FileManager.default.isExecutableFile(atPath: brew) { return brew }
    return bundled
}()

func isRarArchivePath(_ path: String) -> Bool {
    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    if name.hasSuffix(".rar") { return true }
    // Old-style continuation volumes: name.r00, name.r01, ...
    return name.range(of: #"\.r\d{2,}$"#, options: .regularExpression) != nil
}

struct ToolCall {
    var executable: String
    var arguments: [String]
    /// After a successful extract, strip a single newly created root folder here.
    var elimRoot: String? = nil
}

private struct ParsedCommand {
    var command: String
    var archives: [String] = []
    var files: [String] = []
    var dest: String?
    var password: String?
    var passwordGiven = false
    var overwrite: String?
    var excludes: [String] = []
    var fullPaths = false
    var elimRoot = false
    var assumeYes = false
    var literalNames = false
}

/// Turn a 7zz-style argument list into one or more tool invocations.
/// RAR extract (`x`/`e`) and test (`t`) run UnRAR, including multi-volume `.partN.rar`.
/// Everything else, including RAR listing, stays on 7zz.
func planToolCalls(_ args: [String], progress: Bool) -> [ToolCall] {
    guard let command = args.first, !command.isEmpty else { return [ToolCall(executable: SEVENZ, arguments: args)] }
    guard ["x", "e", "t"].contains(command) else { return [sevenCall(args, progress: progress)] }
    var parsed = parseSevenArgs(args)
    parsed.archives = preferFirstRarVolumes(parsed.archives)
    if parsed.archives.isEmpty || !parsed.archives.contains(where: isRarArchivePath) {
        return [sevenCall(args, progress: progress)]
    }
    var calls: [ToolCall] = []
    var plain: [String] = []
    func flushPlain() {
        guard !plain.isEmpty else { return }
        calls.append(sevenCall(rebuildSeven(parsed, archives: plain), progress: progress))
        plain.removeAll()
    }
    for arc in parsed.archives {
        if isRarArchivePath(arc) {
            flushPlain()
            calls.append(unrarCall(parsed, archive: arc))
        } else {
            plain.append(arc)
        }
    }
    flushPlain()
    return calls.isEmpty ? [sevenCall(args, progress: progress)] : calls
}

func unrarMissingText() -> String {
    """
    未找到 UnRAR（\(UNRAR)）。
    这个 RAR 需要随 iDipper 分发的 UnRAR 才能解压或测试。其他格式仍使用 7zz。
    UnRAR was not found. RAR extract and test need the bundled UnRAR tool; other formats still use 7zz.
    """
}

func rarReadOnlyMessage() -> String {
    """
    RAR 压缩包不能修改。UnRAR 的许可只允许解压和测试，不能创建或改写 RAR。
    RAR archives cannot be modified. UnRAR is licensed for extraction and testing only.
    """
}

/// Make UnRAR failures recognizable to the existing password retry (`Wrong password`).
func annotateUnrarResult(_ code: Int32, _ output: String) -> (Int32, String) {
    var text = output.replacingOccurrences(of: "\u{8}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let low = text.lowercased()
    if code != 0 && (code == 11 || low.contains("incorrect password") || low.contains("wrong password")) {
        if !text.contains("Wrong password") { text += text.hasSuffix("\n") ? "Wrong password\n" : "\nWrong password\n" }
    }
    if code != 0 && (low.contains("program aborted") || low.contains("inappropriate ioctl")) {
        text += "\nUnRAR stopped while waiting for input. iDipper runs it non-interactively.\n"
    }
    return (code, text)
}

/// `Extracting  path/file` / `Testing  path/file` activity lines (the percentage is a separate token).
func unrarActivityPath(_ line: String) -> String? {
    for prefix in ["Extracting", "Testing", "Creating"] where line.hasPrefix(prefix) {
        var rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        if rest.hasSuffix("OK") { rest = rest.dropLast(2).trimmingCharacters(in: .whitespaces) }
        if rest.isEmpty || rest == "from" || rest.hasPrefix("from ") { return nil }
        return String(rest)
    }
    return nil
}

func rootSnapshot(_ dest: String?) -> Set<String> {
    guard let dest, !dest.isEmpty else { return [] }
    return Set((try? FileManager.default.contentsOfDirectory(atPath: dest)) ?? [])
}

/// 7-Zip `-spe`: if extraction created a single root folder, move its children up.
func eliminateSingleRoot(_ dest: String, previous: Set<String>) {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(atPath: dest) else { return }
    let fresh = items.filter { !previous.contains($0) }
    guard fresh.count == 1, let name = fresh.first else { return }
    let root = (dest as NSString).appendingPathComponent(name)
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return }
    guard let children = try? fm.contentsOfDirectory(atPath: root), !children.isEmpty else { return }
    let targets = children.map { (from: (root as NSString).appendingPathComponent($0), to: (dest as NSString).appendingPathComponent($0)) }
    if targets.contains(where: { fm.fileExists(atPath: $0.to) }) { return }
    for pair in targets { try? fm.moveItem(atPath: pair.from, toPath: pair.to) }
    if (try? fm.contentsOfDirectory(atPath: root))?.isEmpty == true { try? fm.removeItem(atPath: root) }
}

/// Keep one archive per multi-volume set (lowest `.partN` or the `.rar` before `.rNN`).
/// UnRAR follows the rest of the set from that volume, so extracting every part repeats the same job.
private func preferFirstRarVolumes(_ paths: [String]) -> [String] {
    var best: [String: (order: Int, index: Int)] = [:]
    var drop = Set<Int>()
    for (i, path) in paths.enumerated() {
        guard let id = rarVolumeIdentity(path) else { continue }
        if let prev = best[id.key] {
            if id.order < prev.order {
                drop.insert(prev.index)
                best[id.key] = (id.order, i)
            } else {
                drop.insert(i)
            }
        } else {
            best[id.key] = (id.order, i)
        }
    }
    return paths.enumerated().compactMap { drop.contains($0.offset) ? nil : $0.element }
}

private func rarVolumeIdentity(_ path: String) -> (key: String, order: Int)? {
    let url = URL(fileURLWithPath: path)
    let name = url.lastPathComponent
    let dir = url.deletingLastPathComponent().standardizedFileURL.path.lowercased()
    let ns = name as NSString
    let full = NSRange(location: 0, length: ns.length)
    if let re = try? NSRegularExpression(pattern: #"^(.*)\.part(\d+)\.rar$"#, options: [.caseInsensitive]),
       let m = re.firstMatch(in: name, range: full) {
        let stem = ns.substring(with: m.range(at: 1)).lowercased()
        let order = Int(ns.substring(with: m.range(at: 2))) ?? 0
        return ("part\u{0}\(dir)\u{0}\(stem)", order)
    }
    if let re = try? NSRegularExpression(pattern: #"^(.*)\.r(\d{2,})$"#, options: [.caseInsensitive]),
       let m = re.firstMatch(in: name, range: full) {
        let stem = ns.substring(with: m.range(at: 1)).lowercased()
        let order = (Int(ns.substring(with: m.range(at: 2))) ?? 0) + 1
        return ("old\u{0}\(dir)\u{0}\(stem)", order)
    }
    if name.lowercased().hasSuffix(".rar") {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        return ("old\u{0}\(dir)\u{0}\(stem)", 0)
    }
    return nil
}

private func sevenCall(_ args: [String], progress: Bool) -> ToolCall {
    guard progress, let first = args.first, !first.isEmpty else { return ToolCall(executable: SEVENZ, arguments: args) }
    return ToolCall(executable: SEVENZ, arguments: [first, "-bsp1", "-bb0", "-y"] + args.dropFirst())
}

private func parseSevenArgs(_ args: [String]) -> ParsedCommand {
    var p = ParsedCommand(command: args[0], archives: [], files: [], dest: nil, password: nil, passwordGiven: false, overwrite: nil, excludes: [], fullPaths: false, elimRoot: false, assumeYes: false, literalNames: false)
    var files = false
    for a in args.dropFirst() {
        if files { p.files.append(a); continue }
        if a == "--" { files = true; continue }
        if a == "-an" || a == "-ba" || a == "-slt" || a == "-bb0" || a.hasPrefix("-bsp") || a.hasPrefix("-bso") { continue }
        if a == "-y" { p.assumeYes = true; continue }
        if a == "-spd" { p.literalNames = true; continue }
        if a == "-spf" || a == "-spf2" { p.fullPaths = true; continue }
        if a == "-spe" { p.elimRoot = true; continue }
        if a.hasPrefix("-ai!") { p.archives.append(String(a.dropFirst(4))); continue }
        if a == "-aoa" || a == "-aos" || a == "-aou" || a == "-aot" { p.overwrite = String(a.dropFirst(1)); continue }
        if a.hasPrefix("-x!") { p.excludes.append(String(a.dropFirst(3))); continue }
        if a.hasPrefix("-x") { p.excludes.append(String(a.dropFirst(2))); continue }
        if a.hasPrefix("-o") { p.dest = String(a.dropFirst(2)); continue }
        if a.hasPrefix("-p") { p.passwordGiven = true; p.password = String(a.dropFirst(2)); continue }
        if a.hasPrefix("-") { continue }
        p.archives.append(a)
    }
    return p
}

private func rebuildSeven(_ p: ParsedCommand, archives: [String]) -> [String] {
    var a = [p.command, "-an"] + archives.map { "-ai!" + $0 }
    if let d = p.dest { a.append("-o" + d) }
    if let o = p.overwrite { a.append("-" + o) }
    if p.passwordGiven { a.append("-p" + (p.password ?? "")) }
    if p.fullPaths { a.append("-spf") }
    if p.elimRoot { a.append("-spe") }
    if p.literalNames { a.append("-spd") }
    if p.assumeYes { a.append("-y") }
    for x in p.excludes where !x.isEmpty { a.append("-x!" + x) }
    if !p.files.isEmpty { a += ["--"] + p.files }
    return a
}

private func rarDestination(_ p: ParsedCommand, archive: String) -> String? {
    guard p.command != "t", var dest = p.dest else { return nil }
    if dest.contains("*") {
        dest = dest.replacingOccurrences(of: "*", with: archiveBaseName(URL(fileURLWithPath: archive)))
    }
    return dest.isEmpty ? nil : dest
}

private func unrarCall(_ p: ParsedCommand, archive: String) -> ToolCall {
    var a = [p.command == "e" ? "e" : (p.command == "t" ? "t" : "x")]
    a += ["-y", "-c-", "-cfg-", "-idc"]
    if p.command != "t" {
        switch p.overwrite {
        case "aos": a.append("-o-")
        case "aou", "aot": a.append("-or")
        default: a.append("-o+")
        }
        if p.fullPaths { a.append("-ep3") }
    }
    // `-p-` sets a dummy password and does not prompt. Empty stdin would otherwise abort on encrypted archives.
    if let pw = p.password, !pw.isEmpty { a.append("-p" + pw) } else { a.append("-p-") }
    for x in p.excludes where !x.isEmpty { a.append("-x" + x) }
    let dest = rarDestination(p, archive: archive)
    if let dest { a.append("-op" + dest) }
    a.append(archive)
    if !p.files.isEmpty { a += ["--"] + p.files }
    let strip = (p.command == "x" && p.elimRoot && !p.fullPaths) ? dest : nil
    return ToolCall(executable: UNRAR, arguments: a, elimRoot: strip)
}
