import Foundation
import Network
import AVFoundation
import UIKit
import UserNotifications

// MARK: - 内置 HTTP 推送服务（让 iPhone 自己充当 BARK）

final class PushHTTPServer: ObservableObject {
    @Published var running = false
    @Published var statusText = "未启动"
    @Published var receivedCount = 0
    @Published var lastRawRequest = ""

    var onPush: ((String, String) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "lebark.http.server", qos: .userInitiated)
    private static let boundary = "\r\n\r\n"

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            statusText = "端口无效"
            return
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: nwPort)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.running = true
                        self.statusText = "监听中 · 端口 \(port)"
                    case .failed(let err):
                        self.running = false
                        self.statusText = "失败：\(err.localizedDescription)"
                    case .cancelled:
                        self.running = false
                        self.statusText = "已停止"
                    default:
                        break
                    }
                }
            }
            listener = l
            l.start(queue: queue)
        } catch {
            DispatchQueue.main.async { self.statusText = "启动失败：\(error.localizedDescription)" }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
    }

    // MARK: 连接处理

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readRequest(connection, accumulated: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = accumulated
            if let d = data, !d.isEmpty { buf.append(d) }

            if let req = self.parseHTTP(buf) {
                self.respondAndDeliver(req, on: connection)
                return
            }
            if isComplete || error != nil {
                if let req = self.parseHTTP(buf) {
                    self.respondAndDeliver(req, on: connection)
                } else {
                    connection.cancel()
                }
                return
            }
            self.readRequest(connection, accumulated: buf)
        }
    }

    private struct HTTPReq {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: String
    }

    private func parseHTTP(_ data: Data) -> HTTPReq? {
        guard let raw = String(data: data, encoding: .utf8),
              let headerEnd = raw.range(of: Self.boundary) else { return nil }

        let headerPart = String(raw[raw.startIndex..<headerEnd.lowerBound])
        var bodyPart = String(raw[headerEnd.upperBound...])

        let headerLines = headerPart.components(separatedBy: "\r\n")
        guard let first = headerLines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let target = parts[1]

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                headers[kv[0].lowercased()] = kv[1].trimmingCharacters(in: .whitespaces)
            }
        }

        let targetParts = target.split(separator: "?", maxSplits: 1).map(String.init)
        let path = targetParts.first ?? "/"
        var query: [String: String] = [:]
        if targetParts.count > 1 {
            for pair in targetParts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    query[kv[0].removingPercentEncoding ?? kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        // Content-Length：若 body 尚未收齐则返回 nil 继续读
        if let lenStr = headers["content-length"], let expected = Int(lenStr), expected > 0 {
            if bodyPart.utf8.count < expected { return nil }
            bodyPart = String(decoding: bodyPart.utf8.prefix(expected), as: UTF8.self)
        }

        return HTTPReq(method: method, path: path, query: query, headers: headers, body: bodyPart)
    }

    private func respondAndDeliver(_ req: HTTPReq, on connection: NWConnection) {
        let json = "{\"code\":200,\"message\":\"success\"}"
        let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)"
        connection.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        let (title, body) = extractPayload(req)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.receivedCount += 1
            self.lastRawRequest = "\(req.method) \(req.path) | \(req.body.prefix(60))"
            if !title.isEmpty || !body.isEmpty {
                self.onPush?(title, body)
            }
        }
    }

    /// 兼容多种推送风格：
    /// 1. BARK 风格 GET /<title>/<body>
    /// 2. BARK 风格 GET /<key>/<title>/<body>
    /// 3. query: ?title=xxx&body=xxx（或 text=）
    /// 4. POST JSON {"title":..,"body":..} / {"text":..}
    /// 5. POST form: title=..&body=..
    private func extractPayload(_ req: HTTPReq) -> (String, String) {
        var title = req.query["title"] ?? ""
        var body = req.query["body"] ?? req.query["text"] ?? ""

        if title.isEmpty || body.isEmpty {
            let trimmed = req.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                if let data = trimmed.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    if title.isEmpty {
                        title = (obj["title"] as? String) ?? (obj["group"] as? String) ?? ""
                    }
                    if body.isEmpty {
                        body = (obj["body"] as? String) ?? (obj["text"] as? String)
                            ?? (obj["message"] as? String) ?? (obj["content"] as? String) ?? ""
                    }
                }
            } else if trimmed.contains("=") {
                let kv = Self.parseForm(trimmed)
                if title.isEmpty { title = kv["title"] ?? "" }
                if body.isEmpty { body = kv["body"] ?? kv["text"] ?? "" }
            }
        }

        // BARK path：/标题/正文 或 /key/标题/正文
        if title.isEmpty || body.isEmpty {
            let segs = req.path.split(separator: "/").map(String.init).map { $0.removingPercentEncoding ?? $0 }
            if segs.count >= 2 {
                if title.isEmpty { title = segs[segs.count - 2] }
                if body.isEmpty { body = segs.last ?? "" }
            } else if segs.count == 1, body.isEmpty {
                body = segs[0]
            }
        }

        // 正文里若首行就是 [202]今日汇总，标题留空也能解析
        return (title, body)
    }

    private static func parseForm(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                out[kv[0].removingPercentEncoding ?? kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return out
    }
}

// MARK: - 局域网地址发现

enum NetworkInfo {
    /// 取本机 Wi-Fi（en0）IPv4 地址
    static func localIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            if (flags & IFF_UP) == 0 { continue }
            let name = String(cString: p.pointee.ifa_name)
            let addr = p.pointee.ifa_addr
            if let a = addr, Int32(a.pointee.sa_family) == AF_INET, name == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(a, socklen_t(a.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if !ip.isEmpty { return ip }
            }
        }
        return nil
    }

    static func pushURL(port: UInt16) -> String {
        let ip = localIP() ?? "手机局域网IP"
        return "http://\(ip):\(port)"
    }
}

// MARK: - 后台保活（静音音频，TrollStore 下 audio background 有效）

final class SilenceKeeper {
    static let shared = SilenceKeeper()
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        // 生成 1 秒 44.1kHz 静音 PCM → WAV
        let sampleRate = 44100
        let bytesPerSample = 2
        let frames = sampleRate
        var pcm = [UInt8](repeating: 0, count: frames * bytesPerSample)
        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(contentsOf: u32(UInt32(36 + pcm.count)))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.append(contentsOf: u32(16))
        wav.append(contentsOf: u16(1))
        wav.append(contentsOf: u16(1))
        wav.append(contentsOf: u32(UInt32(sampleRate)))
        wav.append(contentsOf: u32(UInt32(sampleRate * bytesPerSample)))
        wav.append(contentsOf: u16(UInt16(bytesPerSample)))
        wav.append(contentsOf: u16(16))
        wav.append(contentsOf: Array("data".utf8))
        wav.append(contentsOf: u32(UInt32(pcm.count)))
        wav.append(contentsOf: pcm)

        do {
            let p = try AVAudioPlayer(data: wav)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("SilenceKeeper failed: \(error)")
        }
    }

    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private func u32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }
}

// MARK: - 本地通知

enum Notifier {
    static func requestAuth() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func push(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "乐币BARK" : title
        content.body = String(body.prefix(120))
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
