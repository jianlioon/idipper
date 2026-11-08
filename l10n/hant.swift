import Foundation
let terms: [(String, String)] = [("新建文本文档", "新增文字文件"), ("新建", "新增"), ("注释", "註解"), ("历史", "記錄"), ("刷新", "重新整理"), ("解压", "解壓縮"), ("文本", "文字"), ("文件夹", "資料夾"), ("文件管理器", "檔案管理器"), ("文件", "檔案"), ("压缩包", "壓縮檔"), ("默认", "預設"), ("菜单", "選單"), ("设置", "設定"), ("字节", "位元組"), ("线程", "執行緒"), ("内存", "記憶體"), ("程序", "程式"), ("信息", "資訊"), ("视图", "顯示方式"), ("粘贴", "貼上"), ("拷贝", "拷貝"), ("剪切", "剪下"), ("屏幕", "螢幕"), ("网格", "格線"), ("通配符", "萬用字元"), ("参数", "參數"), ("实用工具", "工具程式"), ("右键", "右鍵"), ("服务", "服務"), ("快捷键", "快速鍵"), ("硬盘", "磁碟"), ("应用", "App"), ("项目", "項目"), ("废纸篓", "垃圾桶"), ("创建", "建立"), ("保存", "儲存"), ("路径", "路徑"), ("密码", "密碼"), ("加密", "加密"), ("基准测试", "效能測試"), ("双栏", "雙欄"), ("简介", "資訊")]
let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)!
for line in input.components(separatedBy: "\n") where !line.isEmpty {
    var s = line
    for (a, b) in terms { s = s.replacingOccurrences(of: a, with: b) }
    s = s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    print(s)
}
