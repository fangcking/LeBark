import Foundation

// C 函数指针不能捕获上下文，路径和 handler 都必须是全局的
private let crashLogPath: String = {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("crash_log.txt").path ?? ""
}()

private func lebarkCrashHandler(_ exception: NSException) {
    let stack = exception.callStackSymbols.prefix(14).joined(separator: "\n")
    let text = "崩溃时间：\(Date())\n\(exception.name.rawValue)\n原因：\(exception.reason ?? "未知")\n\n\(stack)\n"
    if !crashLogPath.isEmpty {
        try? text.write(toFile: crashLogPath, atomically: true, encoding: .utf8)
    }
}

/// 记录未捕获异常，便于闪退后直接在设置页看到原因（不用连电脑看日志）
enum CrashLogger {
    private static var fileURL: URL? {
        guard !crashLogPath.isEmpty else { return nil }
        return URL(fileURLWithPath: crashLogPath)
    }

    static func install() {
        NSSetUncaughtExceptionHandler(lebarkCrashHandler)
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
