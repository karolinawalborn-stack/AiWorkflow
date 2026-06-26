import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    // API 配置
    @Published var apiBaseURL: String
    @Published var apiKey: String
    @Published var textModelID: String
    @Published var imageModelID: String
    @Published var imageBaseURL: String
    @Published var imageEndpointPath: String
    @Published var imageReferenceMode: String
    @Published var referenceImageFieldName: String
    @Published var imagePromptFieldName: String
    @Published var isAPIKeyVisible = false
    @Published var validationResult: String?
    @Published var isValidating = false
    @Published var diagnosticLog: String = ""

    // 三套模板
    @Published var topicTemplate: AITemplate
    @Published var copyTemplate: AITemplate
    @Published var promptTemplate: AITemplate
    @Published var showPreviewFor: String? = nil

    init() {
        let s = UserSettings.load()
        self.apiBaseURL = s.apiBaseURL; self.apiKey = s.apiKey
        self.textModelID = s.textModelID; self.imageModelID = s.imageModelID
        self.imageBaseURL = s.imageBaseURL; self.imageEndpointPath = s.imageEndpointPath
        self.imageReferenceMode = s.imageReferenceMode; self.referenceImageFieldName = s.referenceImageFieldName; self.imagePromptFieldName = s.imagePromptFieldName
        let t = AITemplates.load()
        self.topicTemplate = t.topic; self.copyTemplate = t.copywriting; self.promptTemplate = t.imagePrompt
    }

    // MARK: - API 配置

    func save() {
        var s = UserSettings(); s.apiBaseURL = apiBaseURL; s.apiKey = apiKey
        s.textModelID = textModelID; s.imageModelID = imageModelID
        s.imageBaseURL = imageBaseURL; s.imageEndpointPath = imageEndpointPath
        s.imageReferenceMode = imageReferenceMode; s.referenceImageFieldName = referenceImageFieldName; s.imagePromptFieldName = imagePromptFieldName
        s.save()
        saveTemplates()
    }

    func resetAPIToDefaults() {
        apiBaseURL = UserSettings.defaultBaseURL; apiKey = UserSettings.defaultAPIKey
        textModelID = UserSettings.defaultTextModel; imageModelID = UserSettings.defaultImageModel
        imageBaseURL = UserSettings.defaultImageBaseURL; imageEndpointPath = UserSettings.defaultImageEndpointPath
        imageReferenceMode = UserSettings.defaultImageReferenceMode; referenceImageFieldName = UserSettings.defaultReferenceImageFieldName; imagePromptFieldName = UserSettings.defaultImagePromptFieldName
    }

    // MARK: - 快速测试

    func validateConnection() async {
        guard !apiBaseURL.isEmpty else { validationResult = "请填写URL"; return }
        guard !apiKey.isEmpty else { validationResult = "请填写Key"; return }
        isValidating = true; validationResult = nil
        let urlStr = "\(apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/models"
        guard let url = URL(string: urlStr) else { validationResult = "无效URL"; isValidating = false; return }
        var req = URLRequest(url: url); req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); req.timeoutInterval = 15
        let start = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let elapsed = Date().timeIntervalSince(start)
            if let http = resp as? HTTPURLResponse {
                validationResult = http.statusCode == 200
                    ? "✅ Models 接口 OK (\(String(format: "%.1f", elapsed))s)"
                    : "❌ HTTP \(http.statusCode) (\(String(format: "%.1f", elapsed))s)"
            }
        } catch {
            validationResult = classifyError(error, prefix: "")
        }
        isValidating = false
    }

    func shortTest() async {
        guard !apiBaseURL.isEmpty else { validationResult = "请填写URL"; return }
        guard !apiKey.isEmpty else { validationResult = "请填写Key"; return }
        isValidating = true; validationResult = "🔄 短文本测试中..."
        let start = Date()
        let config = AIProviderConfig(baseURL: apiBaseURL, token: apiKey, textModelName: textModelID, imageBaseURL: imageBaseURL, imageEndpointPath: imageEndpointPath, imageModelName: imageModelID, timeout: 30)
        let client = HTTPClient()
        let adapter = InternalToolStationTextAdapter(httpClient: client, config: config)
        do {
            let resp = try await adapter.chatCompletion(systemPrompt: "你是一个助手。", userMessage: "请只回复：ok", temperature: 0.3)
            let elapsed = Date().timeIntervalSince(start)
            validationResult = "✅ 短文本通过 (\(String(format: "%.1f", elapsed))s)\n回复：\(resp.prefix(100))"
        } catch let ne as NetworkError {
            validationResult = "❌ [\(ne.category)] \(ne.errorDescription ?? ""))"
        } catch {
            validationResult = "❌ \(error.localizedDescription)"
        }
        isValidating = false
    }

    // MARK: - 全链路诊断

    func runFullDiagnostics() async {
        diagnosticLog = ""
        isValidating = true
        log("🔍 开始全链路诊断")
        log("")

        // 1. 环境信息
        log("📋 当前配置：")
        log("   文本接口：")
        log("   baseURL = \(apiBaseURL)")
        log("   textModel = \(textModelID)")
        log("   图片接口：")
        log("   imageBaseURL = \(imageBaseURL)")
        log("   imageEndpointPath = \(imageEndpointPath)")
        log("   imageModel = \(imageModelID)")
        log("   最终图片 URL = \(imageBaseURL.trimmingCharacters(in: .init(charactersIn: "/")))/\(imageEndpointPath.trimmingCharacters(in: .init(charactersIn: "/")))")
        log("   通用：")
        log("   token = \(apiKey.prefix(12))...")
        log("")

        // 2. 构造最终请求 URL
        let base = apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let chatURL = "\(base)/v1/chat/completions"
        log("📡 最终请求 URL：")
        log("   \(chatURL)")
        log("")

        // 3. DNS 探测（通过 URL 初始化）
        guard let url = URL(string: chatURL) else {
            log("❌ URL 无效：\(chatURL)")
            isValidating = false; return
        }
        log("✅ URL 格式有效")
        log("   host = \(url.host ?? "nil")")
        log("   scheme = \(url.scheme ?? "nil")")
        log("   path = \(url.path)")
        log("")

        // 4. 网络可达性探测
        log("🌐 网络探测中...")
        let probeStart = Date()
        var probeReq = URLRequest(url: url)
        probeReq.httpMethod = "HEAD"
        probeReq.timeoutInterval = 10
        do {
            let (_, probeResp) = try await URLSession.shared.data(for: probeReq)
            let elapsed = Date().timeIntervalSince(probeStart)
            if let http = probeResp as? HTTPURLResponse {
                log("✅ 服务器可达 (\(String(format: "%.1f", elapsed))s) HTTP \(http.statusCode)")
            }
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                    log("❌ DNS 解析失败：无法解析服务器地址")
                case NSURLErrorCannotConnectToHost:
                    log("❌ 无法连接服务器（端口/防火墙）")
                case NSURLErrorTimedOut:
                    log("⏰ 连接超时（10s）")
                case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                    log("🔒 TLS/证书错误：安全连接失败（可能是证书问题或 ATS 拦截）")
                    log("   请在 Info.plist 添加 NSAppTransportSecurity 例外")
                case NSURLErrorNotConnectedToInternet:
                    log("📡 网络未连接")
                default:
                    log("❌ 网络错误 code=\(ns.code): \(error.localizedDescription)")
                }
            } else {
                log("❌ \(error.localizedDescription)")
            }
            log("")
            log("⚠️ 基础网络探测失败，后续测试可能无意义")
        }
        log("")

        // 5. 发送最小文本请求
        log("📤 发送最小文本测试请求...")
        let testBody: [String: Any] = [
            "model": textModelID,
            "messages": [["role": "user", "content": "请只返回：ok"]],
            "temperature": 0.3,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: testBody) else {
            log("❌ 请求体编码失败")
            isValidating = false; return
        }
        log("   请求体：\(String(data: bodyData, encoding: .utf8) ?? "N/A")")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ]
        req.httpBody = bodyData
        req.timeoutInterval = 60

        log("   Header: Authorization: Bearer \(apiKey.prefix(12))...")
        log("   Header: Content-Type: application/json")
        log("   Timeout: 60s")

        let reqStart = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let elapsed = Date().timeIntervalSince(reqStart)
            guard let http = resp as? HTTPURLResponse else {
                log("❌ 响应非 HTTP")
                isValidating = false; return
            }
            log("✅ 请求完成 (\(String(format: "%.1f", elapsed))s)")
            log("   状态码：HTTP \(http.statusCode)")
            log("   响应头：\(http.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(separator: "\n           "))")
            let rawText = String(data: data, encoding: .utf8) ?? "\(data.count) bytes (binary)"
            log("   原始响应：\(rawText.prefix(1000))")

            // 尝试解析 JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                log("   ✅ JSON 解析成功")
                if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
                    if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                        log("   ✅ 提取到回复内容：\(content.prefix(200))")
                    }
                }
            } else {
                log("   ❌ JSON 解析失败")
            }

        } catch let ns as NSError where ns.domain == NSURLErrorDomain {
            let elapsed = Date().timeIntervalSince(reqStart)
            switch ns.code {
            case NSURLErrorTimedOut:
                log("⏰ 请求超时（60s）")
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid:
                log("🔒 TLS/证书错误：尝试连接时被拒")
                log("   已在 Info.plist 添加 NSAllowsArbitraryLoads，如果仍然失败")
                log("   可能是证书链不被 iOS 信任")
            case NSURLErrorCancelled:
                log("🚫 请求被取消")
            default:
                log("❌ 网络错误 (\(String(format: "%.1f", elapsed))s) code=\(ns.code): \(ns.localizedDescription)")
            }
        } catch {
            log("❌ 未知错误：\(error.localizedDescription)")
        }

        isValidating = false
        log("")
        log("🏁 诊断完成")
    }

    // MARK: - 模板保存

    func saveTemplates() {
        let t = AITemplates(topic: topicTemplate, copywriting: copyTemplate, imagePrompt: promptTemplate)
        t.save()
    }

    func preview(for template: AITemplate) -> String { template.render() }

    func resetAllTemplates() {
        AITemplates.resetToDefaults()
        let t = AITemplates.load()
        topicTemplate = t.topic; copyTemplate = t.copywriting; promptTemplate = t.imagePrompt
    }

    func resetBody(for id: String) {
        switch id {
        case "topic": topicTemplate = topicTemplate.resetBody()
        case "copywriting": copyTemplate = copyTemplate.resetBody()
        case "imagePrompt": promptTemplate = promptTemplate.resetBody()
        default: break
        }
    }

    func resetVariables(for id: String) {
        switch id {
        case "topic": topicTemplate = topicTemplate.resetVariables()
        case "copywriting": copyTemplate = copyTemplate.resetVariables()
        case "imagePrompt": promptTemplate = promptTemplate.resetVariables()
        default: break
        }
    }

    func template(for id: String) -> AITemplate? {
        switch id { case "topic": return topicTemplate; case "copywriting": return copyTemplate; case "imagePrompt": return promptTemplate; default: return nil }
    }

    func updateTemplate(_ t: AITemplate) {
        switch t.id { case "topic": topicTemplate = t; case "copywriting": copyTemplate = t; case "imagePrompt": promptTemplate = t; default: break }
    }

    // MARK: - 工具

    private func log(_ msg: String) {
        print("[D] \(msg)")
        diagnosticLog += msg + "\n"
    }

    private func classifyError(_ error: Error, prefix: String) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut: return "\(prefix)⏰ 请求超时"
            case NSURLErrorNotConnectedToInternet: return "\(prefix)📡 网络未连接"
            case NSURLErrorSecureConnectionFailed: return "\(prefix)🔒 安全连接失败（证书/ATS）"
            case NSURLErrorCannotConnectToHost: return "\(prefix)🔌 无法连接服务器"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "\(prefix)🌐 DNS 解析失败"
            default: return "\(prefix)❌ \(error.localizedDescription)"
            }
        }
        return "\(prefix)❌ \(error.localizedDescription)"
    }
}
