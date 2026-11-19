import Foundation

/// 记录未捕获异常，便于闪退后直接在设置页看到原因（不用连电脑看日志）
enum CrashLogger {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("crash_log.txt")
    }

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(14).joined(separator: "\n")
            let text = "崩溃时间：\(Date())\n\(exception.name.rawValue)\n原因：\(exception.reason ?? "未知")\n\n\(stack)\n"
            if let url = fileURL { try? text.write(to: url, atomically: true, encoding: .utf8) }
        }
    }

    static func read() -> String? {
        guard let url = fileURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
