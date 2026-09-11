import Foundation

/// User-supplied OpenAI-compatible endpoint used to produce context glosses.
struct ProviderSettings: Equatable {
    var enabled: Bool
    var baseURL: String
    var model: String
    var apiKey: String

    static let enabledKey = "provider.enabled"
    static let baseURLKey = "provider.baseURL"
    static let modelKey = "provider.model"
    static let keychainAccount = "provider.apiKey"

    /// The Keychain is consulted once per launch (it can block on a user
    /// prompt); afterwards the key lives here.
    private static var cachedKey: String?
    private static let keyLock = NSLock()

    private static func apiKeyValue() -> String {
        keyLock.lock(); defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }
        // Debug/testing hook: avoid touching the Keychain at all.
        let key = ProcessInfo.processInfo.environment["PODLYRICS_API_KEY"]
            ?? (UserDefaults.standard.bool(forKey: enabledKey) ? Keychain.read(account: keychainAccount) : nil)
            ?? ""
        cachedKey = key
        return key
    }

    static func load() -> ProviderSettings {
        let d = UserDefaults.standard
        return ProviderSettings(
            enabled: d.bool(forKey: enabledKey),
            baseURL: d.string(forKey: baseURLKey) ?? "https://api.openai.com/v1",
            model: d.string(forKey: modelKey) ?? "gpt-4o-mini",
            apiKey: apiKeyValue())
    }

    func save() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: Self.enabledKey)
        d.set(baseURL, forKey: Self.baseURLKey)
        d.set(model, forKey: Self.modelKey)
        Self.keyLock.lock()
        Self.cachedKey = apiKey
        Self.keyLock.unlock()
        Keychain.write(apiKey, account: Self.keychainAccount)
        NotificationCenter.default.post(name: GlossService.settingsDidChange, object: nil)
    }

    var isUsable: Bool {
        enabled && !apiKey.isEmpty && !model.isEmpty && URL(string: baseURL) != nil
    }

    var debugSummary: String {
        "enabled=\(enabled) baseURL=\(baseURL) model=\(model) key=\(apiKey.isEmpty ? "missing" : "set")"
    }

    /// Accepts "https://host", "https://host/v1", "https://host/v1/" and a
    /// full ".../chat/completions"; a bare host gets the conventional "/v1".
    var chatCompletionsURL: URL? {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let base = URL(string: s), base.host != nil else { return nil }
        if s.hasSuffix("/chat/completions") { return base }
        if base.path.isEmpty { return base.appendingPathComponent("v1/chat/completions") }
        return base.appendingPathComponent("chat/completions")
    }
}

/// Asks the Provider for short Chinese glosses of headwords in the context
/// of the sentence they first appear in. Results are written to the
/// UserStore cache; consumers observe `UserStore.glossesDidChange`.
final class GlossService: @unchecked Sendable {
    static let shared = GlossService()
    static let settingsDidChange = Notification.Name("GlossService.settingsDidChange")
    static let batchSize = 40

    private let queue = DispatchQueue(label: "PodLyrics.gloss")
    private var inFlight: Set<String> = []   // transcriptID|headword
    private var session = URLSession(configuration: .default)

    var isEnabled: Bool { ProviderSettings.load().isUsable }

    /// Model name that cached glosses are keyed by; nil when disabled.
    static var activeModel: String? {
        let s = ProviderSettings.load()
        return s.isUsable ? s.model : nil
    }

    typealias Candidate = (headword: String, sentence: String, line: Int)

    func request(transcriptID: String, candidates: [Candidate]) {
        let settings = ProviderSettings.load()
        guard settings.isUsable, !candidates.isEmpty else { return }
        queue.async { [self] in
            let fresh = candidates.filter { !inFlight.contains(transcriptID + "|" + $0.headword) }
            guard !fresh.isEmpty else { return }
            fresh.forEach { inFlight.insert(transcriptID + "|" + $0.headword) }
            let batches = stride(from: 0, to: fresh.count, by: Self.batchSize).map {
                Array(fresh[$0..<min($0 + Self.batchSize, fresh.count)])
            }
            Task.detached(priority: .utility) { [self] in
                for batch in batches {
                    var result = await self.fetch(batch: batch, settings: settings)
                    if result == nil { result = await self.fetch(batch: batch, settings: settings) }
                    if let result { UserStore.shared.saveGlosses(result, transcriptID: transcriptID, model: settings.model) }
                    self.queue.async { batch.forEach { self.inFlight.remove(transcriptID + "|" + $0.headword) } }
                }
            }
        }
    }

    /// One-shot connectivity check for the settings UI.
    func test(settings: ProviderSettings) async -> Result<String, Error> {
        let sample: [Candidate] = [("pivot", "The company decided to pivot to a subscription model.", 0)]
        do {
            let out = try await fetchThrowing(batch: sample, settings: settings)
            if let g = out["pivot"] { return .success("pivot → \(g)") }
            return .failure(NSError(domain: "PodLyrics", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "返回格式不符合预期"]))
        } catch {
            return .failure(error)
        }
    }

    private func fetch(batch: [Candidate], settings: ProviderSettings) async -> [String: String]? {
        do {
            return try await fetchThrowing(batch: batch, settings: settings)
        } catch {
            NSLog("PodLyrics: gloss request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchThrowing(batch: [Candidate], settings: ProviderSettings) async throws -> [String: String] {
        guard let url = settings.chatCompletionsURL else {
            throw NSError(domain: "PodLyrics", code: 2, userInfo: [NSLocalizedDescriptionKey: "Base URL 无效"])
        }
        let items = batch.map { ["word": $0.headword, "sentence": $0.sentence] }
        let userContent = try String(decoding: JSONSerialization.data(withJSONObject: ["items": items]), as: UTF8.self)
        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PodLyrics", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text.prefix(200))"])
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "PodLyrics", code: 3, userInfo: [NSLocalizedDescriptionKey: "响应缺少 choices[0].message.content"])
        }
        return Self.parseGlosses(content, expected: Set(batch.map(\.headword)))
    }

    static let systemPrompt = """
    你是英语播客听力助手。用户给出一组英文单词及其出现的句子。请为每个单词给出它在该句语境下的中文释义，要求：
    - 只解释该句中的用法，不罗列其他义项；
    - 每条不超过 8 个汉字，不要标点、不要拼音、不要英文；
    - 若是习语或口语用法，给出地道的中文对应说法。
    只输出 JSON 对象，形如 {"glosses": {"word": "释义", ...}}，键必须与输入的 word 完全一致。
    """

    static func parseGlosses(_ content: String, expected: Set<String>) -> [String: String] {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let dict = (obj["glosses"] as? [String: Any]) ?? obj
        var out: [String: String] = [:]
        for (k, v) in dict {
            let key = k.lowercased()
            guard expected.contains(key), let s = v as? String else { continue }
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !cleaned.isEmpty { out[key] = String(cleaned.prefix(14)) }
        }
        return out
    }
}
