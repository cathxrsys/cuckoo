import Foundation

struct Window: Identifiable {
    let id = UUID()
    let name: String
    let percent: Double
    let resetsAt: Date?
}

enum FetchError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

private let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 15
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: c)
}()

private func getJSON(_ url: String, headers: [String: String] = [:]) async throws -> [String: Any] {
    var req = URLRequest(url: URL(string: url)!)
    headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
    let (data, resp) = try await session.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else {
        throw FetchError.message(code == 401 || code == 403 ? "токен недействителен (\(code))" : "HTTP \(code)")
    }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FetchError.message("неожиданный ответ")
    }
    return obj
}

private func num(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

private func parseISO(_ s: String?) -> Date? {
    guard var s else { return nil }
    // "2026-11-24T22:30:00.082741+00:00" → отрезаем дробную часть секунд
    if let dot = s.firstIndex(of: "."), let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
        s.removeSubrange(dot..<tz)
    }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Страна по IP

enum Geo {
    /// Код страны текущего внешнего IP. nil — определить не удалось.
    static func country() async -> String? {
        let sources: [(String, (Data) -> String?)] = [
            ("https://api.country.is", { d in
                (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["country"] as? String }),
            ("https://ipinfo.io/country", { d in String(data: d, encoding: .utf8) }),
            ("https://ipapi.co/country/", { d in String(data: d, encoding: .utf8) }),
        ]
        for (url, parse) in sources {
            var req = URLRequest(url: URL(string: url)!)
            req.setValue("LimitsBar", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await session.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let raw = parse(data)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  raw.count == 2, raw.allSatisfy({ $0.isLetter })
            else { continue }
            return raw
        }
        return nil
    }
}

// MARK: - Claude

enum Claude {
    private static func token() throws -> String {
        // через /usr/bin/security: он уже в ACL записи Claude Code, лишних запросов доступа не будет
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let tok = oauth["accessToken"] as? String
        else { throw FetchError.message("нет токена — войди в claude") }
        if let exp = num(oauth["expiresAt"]), Date(timeIntervalSince1970: exp / 1000) < Date() {
            throw FetchError.message("токен истёк — запусти claude")
        }
        return tok
    }

    static func fetch() async throws -> [Window] {
        let obj = try await getJSON("https://api.anthropic.com/api/oauth/usage", headers: [
            "Authorization": "Bearer \(try token())",
            "anthropic-beta": "oauth-2025-04-20",
        ])
        let names: [(String, String)] = [
            ("five_hour", "5 часов"), ("seven_day", "Неделя"),
            ("seven_day_opus", "Неделя · Opus"), ("seven_day_sonnet", "Неделя · Sonnet"),
        ]
        return names.compactMap { key, name in
            guard let w = obj[key] as? [String: Any], let p = num(w["utilization"]) else { return nil }
            return Window(name: name, percent: p, resetsAt: parseISO(w["resets_at"] as? String))
        }
    }
}

// MARK: - Codex

enum Codex {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")

    static func fetch() async throws -> [Window] {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["tokens"] as? [String: Any],
              let tok = t["access_token"] as? String
        else { throw FetchError.message("нет токена — войди в codex") }
        var headers = ["Authorization": "Bearer \(tok)", "User-Agent": "LimitsBar"]
        if let acc = t["account_id"] as? String { headers["ChatGPT-Account-Id"] = acc }

        let r = try await getJSON("https://chatgpt.com/backend-api/wham/usage", headers: headers)
        guard let rl = r["rate_limit"] as? [String: Any] else { throw FetchError.message("нет rate_limit") }
        return ["primary_window", "secondary_window"].compactMap { key in
            guard let w = rl[key] as? [String: Any], let p = num(w["used_percent"]) else { return nil }
            let reset = num(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            return Window(name: windowName(num(w["limit_window_seconds"])), percent: p, resetsAt: reset)
        }
    }

    private static func windowName(_ secs: Double?) -> String {
        guard let s = secs else { return "Окно" }
        if s >= 6 * 86400 { return "Неделя" }
        if s >= 86400 { return "\(Int(s / 86400)) дн." }
        return "\(Int((s / 3600).rounded())) часов"
    }
}
