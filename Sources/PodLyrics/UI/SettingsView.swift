import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LibraryModel
    @State private var settings = ProviderSettings.load()
    @State private var saved = ProviderSettings.load()
    @State private var testing = false
    @State private var testResult: String?
    @State private var testFailed = false
    @FocusState private var focus: Field?

    private enum Field { case baseURL, model, apiKey }

    private var dirty: Bool { settings != saved }

    var body: some View {
        Form {
            Section {
                Picker("我的水平", selection: $model.proficiency) {
                    ForEach(Proficiency.choices) { Text($0.displayName).tag($0) }
                }
                Text("该档及以下的词视为已掌握，字幕中只标注更高档的词。生词本里的词始终标注，标为已掌握的词永不标注。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("词汇")
            }

            Section {
                Toggle("启用语境释义", isOn: $settings.enabled)
                TextField("Base URL", text: $settings.baseURL, prompt: Text("https://api.openai.com/v1"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .baseURL)
                    .disabled(!settings.enabled)
                TextField("模型", text: $settings.model, prompt: Text("gpt-4o-mini"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .model)
                    .disabled(!settings.enabled)
                SecureField("API Key", text: $settings.apiKey, prompt: Text("sk-…"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .apiKey)
                    .disabled(!settings.enabled)
                HStack {
                    Button("保存") {
                        focus = nil
                        settings.save()
                        saved = settings
                        testResult = nil
                    }
                    .disabled(!dirty)
                    Button("测试连接") { runTest() }
                        .disabled(testing || !settings.isUsable)
                    if testing { ProgressView().controlSize(.small) }
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testFailed ? .red : .green)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                Text("使用任何 OpenAI 兼容接口（OpenAI、DeepSeek、Moonshot、Ollama、公司中继等）。Base URL 填到 /v1 为止即可，例如 https://api.openai.com/v1。开启后，字幕里被标注的词和它所在的句子会发送给该服务以获取更贴合语境的释义；结果按剧集缓存在本机，不重复请求。关闭时应用完全离线。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("API Key 保存在 macOS 钥匙串中。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("语境释义（可选，需要自备模型服务）")
            }

            Section {
                LabeledContent("词典") {
                    Text(Lexicon.shared.isAvailable ? "ECDICT 1.0.28（内置，离线）" : "未找到 lexicon.sqlite")
                }
                LabeledContent("用户数据") {
                    Text(UserStore.directory.path)
                        .textSelection(.enabled)
                        .font(.caption)
                }
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }

    private func runTest() {
        testing = true
        testResult = nil
        let s = settings
        Task {
            let result = await GlossService.shared.test(settings: s)
            await MainActor.run {
                testing = false
                switch result {
                case .success(let msg): testFailed = false; testResult = "连接成功：\(msg)"
                case .failure(let err): testFailed = true; testResult = err.localizedDescription
                }
            }
        }
    }
}
