import SwiftUI
#if os(iOS)
import UIKit
import Photos
#endif

@MainActor
final class ImageGenViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var progressText: String = ""
    @Published var errorMessage: String?
    @Published var exportMessage: String?
    @Published var currentGeneratingIndex: Int? = nil
    @Published var project: Project?

    // 多参考图
    @Published var referenceImages: [ReferenceImage] = []
    @Published var useReferenceImages = false

    private var store: ProjectStore?
    private var imageService: AIImageServiceProtocol?
    private var currentTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    var imageCards: [ImageCard] { project?.sortedImages ?? [] }
    var successCount: Int { imageCards.filter { $0.status == .success }.count }
    var allSuccess: Bool { !imageCards.isEmpty && imageCards.allSatisfy { $0.status == .success } }

    // 轮询和下载候选路径
    private let queryPaths: [String] = {
        let c = AIProviderConfig.default.imageTaskQueryEndpointPath
        var p = [c]; for x in AIProviderConfig.candidateQueryPaths { if !p.contains(x) { p.append(x) } }; return p
    }()
    private let efsPaths: [String] = AIProviderConfig.efsDownloadPaths

    // MARK: - 设置

    func setup(store: ProjectStore, imageService: AIImageServiceProtocol, project: Project) {
        self.store = store; self.imageService = imageService; self.project = project
        self.referenceImages = project.referenceImages
        self.useReferenceImages = project.useGlobalReferenceImage
        print("📷 setup: cards=\(project.imageCards.count) refs=\(project.referenceImages.count)")
    }
    deinit { currentTask?.cancel(); pollingTask?.cancel() }

    // MARK: - 多参考图管理

    func addReferenceImages(from urls: [URL]) {
        var refs: [ReferenceImage] = []
        for (i, url) in urls.enumerated() {
            guard let data = try? Data(contentsOf: url) else { continue }
            let fileName = "ref_\(UUID().uuidString.prefix(8)).jpg"
            guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { continue }
            let dest = docDir.appendingPathComponent(fileName)
            guard (try? data.write(to: dest)) != nil else { continue }
            refs.append(ReferenceImage(localFilePath: dest.path, fileName: fileName, sortOrder: referenceImages.count + i))
        }
        referenceImages.append(contentsOf: refs)
        useReferenceImages = true
        saveReferenceImages()
    }

    func removeReferenceImage(at id: UUID) {
        referenceImages.removeAll { $0.id == id }
        if referenceImages.isEmpty { useReferenceImages = false }
        saveReferenceImages()
    }

    func clearAllReferenceImages() {
        referenceImages = []; useReferenceImages = false
        saveReferenceImages()
    }

    private func saveReferenceImages() {
        guard var p = project else { return }
        p.referenceImages = referenceImages
        p.useGlobalReferenceImage = useReferenceImages
        p.updatedAt = Date(); store?.upsert(p); project = p
    }

    // MARK: - 单张生成

    func generateImage(at index: Int) async {
        let tag = "📷[\(index)]"
        print("\n\(tag) ===== 第\(index+1)张 =====")
        guard let imgSvc = imageService else { setCardFailed(index, .failed, "服务未初始化"); return }
        guard var p = project, index < p.imageCards.count else { setCardFailed(index, .failed, "索引无效"); return }

        let promptText: String
        if index < p.promptCards.count, !p.promptCards[index].promptText.isEmpty { promptText = p.promptCards[index].promptText }
        else { promptText = "A cute white round-headed cartoon character, dark blue-black background, dual-panel comic, 3:4 ratio" }
        let size = AIProviderConfig.resolveImageSize(ratio: p.ratio, override: p.imageSizeOverride)
        print("\(tag) 尺寸: \(size) refs=\(referenceImages.count)")

        currentGeneratingIndex = index
        p.imageCards[index].status = .generating; p.imageCards[index].promptText = promptText; p.imageCards[index].errorMessage = nil
        project = p

        let start = Date()
        do {
            let results: [ImageGenerationResult]
            if useReferenceImages, let firstRef = referenceImages.first, let d = try? Data(contentsOf: URL(fileURLWithPath: firstRef.localFilePath)) {
                results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1, referenceImageBase64: d.base64EncodedString(), referenceMode: "promptOnlyFallback")
            } else {
                results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1)
            }
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(start)
            print("\(tag) ✅ API (\(String(format: "%.1f", elapsed))s)")

            guard let result = results.first else { setCardFailed(index, .parseFailed, "空结果"); currentGeneratingIndex = nil; return }

            // 处理 task_id 或图片数据
            if let taskID = result.taskID {
                print("\(tag) ⏳ taskID=\(taskID)")
                guard var p2 = project, index < p2.imageCards.count else { return }
                p2.imageCards[index].status = .taskAccepted; p2.imageCards[index].taskId = taskID
                p2.imageCards[index].rawSubmitResponse = result.rawResponseText ?? ""
                p2.imageCards[index].errorMessage = "任务: \(taskID)"
                p2.updatedAt = Date(); store?.upsert(p2); project = p2
                currentGeneratingIndex = nil
                startPolling(taskID: taskID, cardIndex: index)
                return
            }

            // 直接返回图片数据
            try await processDirectResult(index: index, result: result)

        } catch is CancellationError { setCardFailed(index, .cancelled, "取消"); currentGeneratingIndex = nil
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorCancelled: setCardFailed(index, .cancelled, "后台中断")
                case NSURLErrorBadURL, NSURLErrorUnsupportedURL: setCardFailed(index, .failed, "URL 无效")
                case NSURLErrorCannotConnectToHost: setCardFailed(index, .failed, "无法连接服务器")
                case NSURLErrorTimedOut: setCardFailed(index, .failed, "请求超时")
                default: setCardFailed(index, .failed, "网络错误")
                }
            } else if let ne = error as? NetworkError, case .httpError(let code, let msg, _) = ne {
                setCardFailed(index, .failed, "服务器(HTTP \(code)): \((msg ?? "").prefix(300))", rawResponse: msg ?? "")
            } else { setCardFailed(index, .failed, error.localizedDescription) }
            currentGeneratingIndex = nil
        }
    }

    // 直接图片结果
    private func processDirectResult(index: Int, result: ImageGenerationResult) async throws {
        if let data = result.imageData, !data.isEmpty {
            try await saveImageLocally(index: index, imageData: data, rawText: result.rawResponseText ?? "")
            return
        }
        if let urlStr = result.imageURL, let url = URL(string: urlStr) {
            if let (d, _) = try? await URLSession.shared.data(for: .init(url: url, timeoutInterval: 30)), !d.isEmpty {
                try await saveImageLocally(index: index, imageData: d, rawText: result.rawResponseText ?? "")
                return
            }
        }
        setCardFailed(index, .parseFailed, "无图片数据", rawResponse: result.rawResponseText ?? "无返回")
        currentGeneratingIndex = nil
    }

    // MARK: - 轮询（自动尝试 efsIds 下载）

    private func startPolling(taskID: String, cardIndex: Int) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            let tag = "📷[\(cardIndex)]"; let maxAttempts = 60
            let base = AIProviderConfig.default.imageBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
            print("\(tag) ⏳ 轮询 taskID=\(taskID) max=\(maxAttempts)")

            if var p = self.project, cardIndex < p.imageCards.count {
                p.imageCards[cardIndex].status = .polling; p.imageCards[cardIndex].errorMessage = "查询: \(taskID)"
                p.updatedAt = Date(); self.store?.upsert(p); self.project = p
            }

            for attempt in 1...maxAttempts {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                print("\(tag) 🔄 \(attempt)/\(maxAttempts)")

                // 先通过 efsIds 直接下载（如果已有）
                if var p2 = self.project, cardIndex < p2.imageCards.count, !p2.imageCards[cardIndex].efsIds.isEmpty {
                    print("\(tag) 📦 efsIds=\(p2.imageCards[cardIndex].efsIds)")
                    for efsId in p2.imageCards[cardIndex].efsIds {
                        if await self.tryDownloadEFS(efsId: efsId, cardIndex: cardIndex, base: base, raw: "") { return }
                    }
                }

                // 查询任务结果
                for path in self.queryPaths {
                    if Task.isCancelled { break }
                    let pp = path.hasPrefix("/") ? path : "/\(path)"
                    for (qURL, method) in [("\(base)\(pp)?task_id=\(taskID)", "GET"), ("\(base)\(pp)", "POST")] {
                        if Task.isCancelled { break }
                        let body = method == "POST" ? try? JSONSerialization.data(withJSONObject: ["task_id": taskID], options: []) : nil
                        let req = APIRequest(method: method == "GET" ? .get : .post, url: qURL, headers: ["Content-Type": "application/json"], body: body, timeout: 10)
                        do {
                            let r = try await HTTPClient().sendRaw(req); let rs = String(data: r.data, encoding: .utf8) ?? ""
                            // 保存查询响应
                            if var p3 = self.project, cardIndex < p3.imageCards.count {
                                p3.imageCards[cardIndex].rawQueryResponse = rs; self.store?.upsert(p3); self.project = p3
                            }
                            // 解析 efsIds
                            if let json = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any],
                               let d = json["data"] as? [String: Any],
                               let efs = d["efsIds"] as? [String] {
                                if var p3 = self.project, cardIndex < p3.imageCards.count {
                                    p3.imageCards[cardIndex].efsIds = efs; self.store?.upsert(p3); self.project = p3
                                }
                                for efsId in efs { if await self.tryDownloadEFS(efsId: efsId, cardIndex: cardIndex, base: base, raw: rs) { return } }
                            }
                            // 标准字段
                            let parsed = FlexibleImageResponseParser.parse(from: r.data)
                            if let b64 = parsed.base64, let d = Data(base64Encoded: b64) { await self.saveFromPolling(cardIndex, d, rs); return }
                            if let u = parsed.url, let url = URL(string: u), let (d,_) = try? await URLSession.shared.data(for: .init(url: url, timeoutInterval: 15)) { await self.saveFromPolling(cardIndex, d, rs); return }
                            // 任务状态
                            if rs.contains("success")||rs.contains("completed")||rs.contains("finished") { print("\(tag) 完成,等图片") }
                            if rs.contains("failed")||rs.contains("error") { self.markFailed(cardIndex, "任务失败"); return }
                            if rs.contains("processing")||rs.contains("pending")||rs.contains("queued") { break } // 继续等
                        } catch { print("\(tag) ⚠️ \(method) \(path): \(error.localizedDescription)") }
                    }
                }
            }
            // 超时
            if var p = self.project, cardIndex < p.imageCards.count, p.imageCards[cardIndex].status == .polling {
                p.imageCards[cardIndex].status = .timeout; p.imageCards[cardIndex].errorMessage = "查询超时(120s)"
                p.updatedAt = Date(); self.store?.upsert(p); self.project = p
            }
        }
    }

    /// 尝试通过 efsId 从候选路径下载
    private func tryDownloadEFS(efsId: String, cardIndex: Int, base: String, raw: String) async -> Bool {
        for ep in efsPaths {
            let pp = ep.hasPrefix("/") ? ep : "/\(ep)"
            for urlStr in ["\(base)\(pp)/\(efsId)", "\(base)\(pp)?file_id=\(efsId)", "\(base)\(pp)?efsId=\(efsId)"] {
                guard let url = URL(string: urlStr) else { continue }
                print("📷[\(cardIndex)] ⏳ efs下载: \(urlStr)")
                if let (d, _) = try? await URLSession.shared.data(for: .init(url: url, timeoutInterval: 15)), d.count > 200 {
                    await self.saveFromPolling(cardIndex, d, raw)
                    return true
                }
            }
        }
        return false
    }

    // MARK: - 保存

    private func saveImageLocally(index: Int, imageData: Data, rawText: String) async throws {
        #if os(iOS)
        guard UIImage(data: imageData) != nil else { setCardFailed(index, .parseFailed, "无法解码"); return }
        #endif
        let fn = "img_\(project?.id.uuidString.prefix(8) ?? "x")_\(index).jpg"
        guard let dd = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { setCardFailed(index, .saveFailed, "无目录"); return }
        let fu = dd.appendingPathComponent(fn)
        do { try imageData.write(to: fu); print("📷[\(index)] ✅ 保存: \(fu.path)") }
        catch { setCardFailed(index, .saveFailed, "保存失败: \(error.localizedDescription)"); return }
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .success; p.imageCards[index].imageBase64 = imageData.base64EncodedString()
        p.imageCards[index].localFilePath = fu.path; p.imageCards[index].rawSubmitResponse = rawText; p.imageCards[index].errorMessage = nil
        if p.imageCards.allSatisfy({ $0.status == .success }) { p.status = .imagesReady }
        p.updatedAt = Date(); store?.upsert(p); project = p
        currentGeneratingIndex = nil
    }

    @MainActor private func saveFromPolling(_ idx: Int, _ d: Data, _ rs: String) {
        #if os(iOS)
        guard UIImage(data: d) != nil else { setCardFailed(idx, .parseFailed, "无法解码", rawResponse: rs); return }
        #endif
        let fn = "img_\(project?.id.uuidString.prefix(8) ?? "x")_\(idx).jpg"
        guard let dd = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { setCardFailed(idx, .saveFailed, "无目录"); return }
        let fu = dd.appendingPathComponent(fn)
        do { try d.write(to: fu); print("📷[\(idx)] ✅ 轮询保存: \(fu.path)") }
        catch { setCardFailed(idx, .saveFailed, "保存失败: \(error.localizedDescription)"); return }
        guard var p = project, idx < p.imageCards.count else { return }
        p.imageCards[idx].status = .success; p.imageCards[idx].imageBase64 = d.base64EncodedString()
        p.imageCards[idx].localFilePath = fu.path; p.imageCards[idx].rawQueryResponse = rs; p.imageCards[idx].errorMessage = nil
        if p.imageCards.allSatisfy({ $0.status == .success }) { p.status = .imagesReady }
        p.updatedAt = Date(); store?.upsert(p); project = p
        print("📷[\(idx)] ✅ 轮询完成")
    }

    private func setCardFailed(_ idx: Int, _ st: ImageStatus, _ err: String, rawResponse: String = "") {
        guard var p = project, idx < p.imageCards.count else { return }
        p.imageCards[idx].status = st; p.imageCards[idx].errorMessage = err
        if !rawResponse.isEmpty { p.imageCards[idx].rawSubmitResponse = rawResponse }
        p.updatedAt = Date(); store?.upsert(p); project = p
        print("📷[\(idx)] ❌ \(st.rawValue): \(err)")
        errorMessage = err
    }
    private func markFailed(_ idx: Int, _ err: String) { setCardFailed(idx, .failed, err) }

    // MARK: - 测试

    func generateTestImage(at index: Int) {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].promptText = "A cute white round-headed cartoon character in dark blue-black room, dual-panel comic, 3:4 ratio"
        project = p; store?.upsert(p)
        Task { await generateImage(at: index); if let np = project { store?.upsert(np) } }
    }

    // MARK: - 批量

    func generateAllImages() {
        print("\n🔵 [ImageGen] 批量开始")
        guard let p = project else { errorMessage = "无项目"; return }
        let fp: Project
        if let s = store, let r = s.project(id: p.id) { fp = r; project = r } else { fp = p }
        let toGen = fp.imageCards.indices.filter { fp.imageCards[$0].status != .success }
        if toGen.isEmpty { return }
        currentTask?.cancel()
        isLoading = true; errorMessage = nil; progressText = ""
        var np = fp; for i in toGen { np.imageCards[i].status = .idle; np.imageCards[i].errorMessage = nil }
        project = np; store?.upsert(np)
        currentTask = Task {
            for (li, idx) in toGen.enumerated() {
                if Task.isCancelled { break }
                progressText = "\(li+1)/\(toGen.count)张..."
                await generateImage(at: idx)
                if let np2 = project { store?.upsert(np2) }
            }
            isLoading = false; currentGeneratingIndex = nil
            progressText = successCount == imageCards.count ? "全部完成" : "\(successCount)/\(imageCards.count)"
        }
    }

    func regenerateImage(at index: Int) {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .idle; p.imageCards[index].errorMessage = nil
        p.imageCards[index].imageBase64 = nil; p.imageCards[index].localFilePath = nil
        project = p; store?.upsert(p)
        Task { await generateImage(at: index); if let np2 = project { store?.upsert(np2) } }
    }

    // MARK: - 一键下载到相册

    func downloadAllToAlbum() {
        #if os(iOS)
        let cards = imageCards.filter { $0.status == .success && $0.localFilePath != nil }
        guard !cards.isEmpty else { errorMessage = "没有可下载的图片"; return }
        PHPhotoLibrary.requestAuthorization { s in
            guard s == .authorized || s == .limited else { DispatchQueue.main.async { self.errorMessage = "无相册权限" }; return }
            var saved = 0; var failed = 0; var errs: [String] = []
            for c in cards {
                guard let path = c.localFilePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let ui = UIImage(data: data) else { failed += 1; errs.append("图\(c.cardIndex+1): 读取失败"); continue }
                PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: ui) } completionHandler: { ok, err in
                    if ok { saved += 1 } else { failed += 1; errs.append("图\(c.cardIndex+1): \(err?.localizedDescription ?? "?")") }
                    if saved + failed == cards.count {
                        DispatchQueue.main.async {
                            self.exportMessage = failed == 0 ? "✅ \(saved)张已保存" : "\(saved)成功 \(failed)失败"
                            if !errs.isEmpty { self.errorMessage = errs.prefix(3).joined(separator: "\n") }
                        }
                    }
                }
            }
        }
        #endif
    }

    // MARK: - 相册 & 完成

    func saveToAlbum(at index: Int) {
        #if os(iOS)
        guard index < imageCards.count, imageCards[index].status == .success,
              let data = imageCards[index].decodedImageData, let ui = UIImage(data: data) else { errorMessage = "图片不存在"; return }
        PHPhotoLibrary.requestAuthorization { s in
            guard s == .authorized || s == .limited else { DispatchQueue.main.async { self.errorMessage = "无权限" }; return }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: ui) } completionHandler: { ok, err in
                DispatchQueue.main.async { if ok { self.exportMessage = "已保存" } else { self.errorMessage = "保存失败: \(err?.localizedDescription ?? "")" } }
            }
        }
        #endif
    }
    func completeProject() {
        guard var p = project else { return }; p.status = .completed; p.updatedAt = Date(); store?.upsert(p); project = p
    }
}
