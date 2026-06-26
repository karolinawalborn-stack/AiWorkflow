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

    @Published var selectedReferenceImageData: Data? = nil
    @Published var useGlobalReferenceImage = false
    @Published var referenceImageFilePath: String? = nil

    private var store: ProjectStore?
    private var imageService: AIImageServiceProtocol?
    private var currentTask: Task<Void, Never>?

    var imageCards: [ImageCard] { project?.sortedImages ?? [] }
    var successCount: Int { imageCards.filter { $0.status == .success }.count }
    var allSuccess: Bool { !imageCards.isEmpty && imageCards.allSatisfy { $0.status == .success } }

    // MARK: - 设置

    func setup(store: ProjectStore, imageService: AIImageServiceProtocol, project: Project) {
        self.store = store; self.imageService = imageService; self.project = project
        self.useGlobalReferenceImage = project.useGlobalReferenceImage
        self.referenceImageFilePath = project.globalReferenceImageLocalPath
        if let path = project.globalReferenceImageLocalPath {
            self.selectedReferenceImageData = try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        print("📷 [ImageGen] setup: cards=\(project.imageCards.count) ref=\(project.useGlobalReferenceImage)")
    }
    deinit { currentTask?.cancel() }

    // MARK: - 参考图

    func setReferenceImage(data: Data, filePath: String) {
        selectedReferenceImageData = data; referenceImageFilePath = filePath; useGlobalReferenceImage = true
        guard var p = project else { return }
        p.globalReferenceImageLocalPath = filePath; p.useGlobalReferenceImage = true; p.updatedAt = Date()
        store?.upsert(p); project = p
    }
    func clearReferenceImage() {
        selectedReferenceImageData = nil; referenceImageFilePath = nil; useGlobalReferenceImage = false
        guard var p = project else { return }
        p.globalReferenceImageLocalPath = nil; p.useGlobalReferenceImage = false; p.updatedAt = Date()
        store?.upsert(p); project = p
    }

    // MARK: - 单张生成

    func generateImage(at index: Int) async {
        let tag = "📷[\(index)]"
        print("\n\(tag) ===== 第\(index+1)张 =====")

        guard let imgSvc = imageService else { setCardFailed(index, status: .failed, error: "服务未初始化"); return }
        guard var p = project, index < p.imageCards.count else { setCardFailed(index, status: .failed, error: "索引无效"); return }

        let promptText: String
        if index < p.promptCards.count, !p.promptCards[index].promptText.isEmpty { promptText = p.promptCards[index].promptText }
        else { promptText = "A cute white round-headed cartoon character, dark blue-black background, dual-panel comic, 3:4 ratio" }
        let size = p.ratio == "3:4" ? "1024x1792" : "1024x1024"

        var refB64: String? = nil; let refMode: String
        if useGlobalReferenceImage, let data = selectedReferenceImageData { refB64 = data.base64EncodedString(); refMode = p.globalReferenceImageMode.rawValue }
        else { refMode = "disabled" }

        currentGeneratingIndex = index
        p.imageCards[index].status = .generating
        p.imageCards[index].promptText = promptText
        p.imageCards[index].errorMessage = nil
        project = p

        let start = Date()
        do {
            let results: [ImageGenerationResult]
            if refMode != "disabled", let refB64 = refB64 {
                results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1, referenceImageBase64: refB64, referenceMode: refMode)
            } else {
                results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1)
            }
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(start)
            print("\(tag) ✅ API (\(String(format: "%.1f", elapsed))s) results=\(results.count)")

            guard let result = results.first else { setCardFailed(index, status: .parseFailed, error: "空结果"); currentGeneratingIndex = nil; return }
            try await processResult(index: index, result: result)

        } catch is CancellationError { setCardFailed(index, status: .cancelled, error: "请求被取消"); currentGeneratingIndex = nil
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorCancelled: setCardFailed(index, status: .cancelled, error: "后台中断")
                case NSURLErrorBadURL, NSURLErrorUnsupportedURL: setCardFailed(index, status: .failed, error: "URL 无效，请在设置中检查")
                case NSURLErrorCannotConnectToHost: setCardFailed(index, status: .failed, error: "无法连接服务器")
                case NSURLErrorTimedOut: setCardFailed(index, status: .failed, error: "请求超时")
                default: setCardFailed(index, status: .failed, error: "网络错误: \(error.localizedDescription)")
                }
            } else { setCardFailed(index, status: .failed, error: error.localizedDescription) }
            currentGeneratingIndex = nil
        }
    }

    /// 处理结果：始终保存 rawResponseText，支持 data/url/taskID 三种模式
    private func processResult(index: Int, result: ImageGenerationResult) async throws {
        let tag = "📷[\(index)]"
        let rawText = result.rawResponseText ?? ""

        // 1. 有图片数据
        if let data = result.imageData, !data.isEmpty {
            print("\(tag) ✅ 图片数据: \(data.count) bytes")
            try await saveImageLocally(index: index, imageData: data, result: result)
            return
        }

        // 2. 有 URL → 下载
        if let urlStr = result.imageURL, let url = URL(string: urlStr) {
            print("\(tag) URL: \(urlStr)")
            do {
                let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 30))
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if !data.isEmpty { try await saveImageLocally(index: index, imageData: data, result: result); return }
                setCardFailed(index, status: .parseFailed, error: "URL 下载空 (HTTP \(code))", rawResponse: rawText)
            } catch { setCardFailed(index, status: .parseFailed, error: "下载失败: \(error.localizedDescription)", rawResponse: rawText) }
            currentGeneratingIndex = nil; return
        }

        // 3. 异步任务
        if let taskID = result.taskID {
            print("\(tag) ⏳ 异步任务: taskID=\(taskID)")
            guard var p = project, index < p.imageCards.count else { return }
            p.imageCards[index].status = .taskAccepted
            p.imageCards[index].rawResponse = rawText
            p.imageCards[index].errorMessage = "已接收任务: \(taskID)"
            p.updatedAt = Date(); store?.upsert(p); project = p
            currentGeneratingIndex = nil; return
        }

        // 4. 无法解析
        let displayText = rawText.isEmpty ? (result.revisedPrompt ?? "无返回数据") : rawText
        print("\(tag) ❌ 无法解析. rawText=\(displayText.prefix(200))")
        setCardFailed(index, status: .parseFailed, error: "返回成功但无法解析图片格式", rawResponse: displayText)
        currentGeneratingIndex = nil
    }

    private func saveImageLocally(index: Int, imageData: Data, result: ImageGenerationResult) async throws {
        let tag = "📷[\(index)]"
        #if os(iOS)
        guard UIImage(data: imageData) != nil else { setCardFailed(index, status: .parseFailed, error: "无法解码 UIImage"); return }
        #endif
        let fileName = "img_\(project?.id.uuidString.prefix(8) ?? "x")_\(index).jpg"
        guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            setCardFailed(index, status: .saveFailed, error: "无法获取文档目录"); return
        }
        let fileURL = docDir.appendingPathComponent(fileName)
        do { try imageData.write(to: fileURL); print("\(tag) ✅ 本地保存: \(fileURL.path)") }
        catch { setCardFailed(index, status: .saveFailed, error: "保存失败: \(error.localizedDescription)"); return }

        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .success
        p.imageCards[index].imageBase64 = imageData.base64EncodedString()
        p.imageCards[index].localFilePath = fileURL.path
        p.imageCards[index].imageURL = result.imageURL
        p.imageCards[index].rawResponse = result.rawResponseText ?? ""
        p.imageCards[index].errorMessage = nil
        if p.imageCards.allSatisfy({ $0.status == .success }) { p.status = .imagesReady }
        p.updatedAt = Date(); store?.upsert(p); project = p
        currentGeneratingIndex = nil
        print("\(tag) ✅ 完成: \(fileURL.lastPathComponent)")
    }

    private func setCardFailed(_ index: Int, status: ImageStatus, error: String, rawResponse: String = "") {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = status; p.imageCards[index].errorMessage = error
        if !rawResponse.isEmpty { p.imageCards[index].rawResponse = rawResponse }
        p.updatedAt = Date(); store?.upsert(p); project = p
        print("📷[\(index)] ❌ \(status.rawValue): \(error)")
        errorMessage = error
    }

    // MARK: - 测试

    func generateTestImage(at index: Int) {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].promptText = "A cute white round-headed cartoon character in dark blue-black room, dual-panel comic, 3:4 ratio"
        project = p; store?.upsert(p)
        Task { await generateImage(at: index); if let np = project { store?.upsert(np) } }
    }

    // MARK: - 批量

    func generateAllImages() {
        print("\n🔵 [ImageGen] ===== 批量 =====")
        guard let p = project else { errorMessage = "项目未加载"; return }
        let fp: Project
        if let s = store, let r = s.project(id: p.id) { fp = r; project = r } else { fp = p }
        let toGenerate = fp.imageCards.indices.filter { fp.imageCards[$0].status != .success }
        if toGenerate.isEmpty { return }
        currentTask?.cancel()
        isLoading = true; errorMessage = nil; progressText = ""
        var np = fp
        for idx in toGenerate { np.imageCards[idx].status = .idle; np.imageCards[idx].errorMessage = nil }
        project = np; store?.upsert(np)
        currentTask = Task {
            for (li, idx) in toGenerate.enumerated() {
                if Task.isCancelled { break }
                progressText = "生成第\(li+1)/\(toGenerate.count)张..."
                await generateImage(at: idx)
                if let np2 = project { store?.upsert(np2) }
            }
            isLoading = false; currentGeneratingIndex = nil
            progressText = successCount == imageCards.count ? "全部完成" : "\(successCount)/\(imageCards.count) 张完成"
        }
    }

    func regenerateImage(at index: Int) {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .idle; p.imageCards[index].errorMessage = nil
        p.imageCards[index].imageBase64 = nil; p.imageCards[index].localFilePath = nil
        project = p; store?.upsert(p)
        Task { await generateImage(at: index); if let np2 = project { store?.upsert(np2) } }
    }

    // MARK: - 相册 & 完成

    func saveToAlbum(at index: Int) {
        #if os(iOS)
        guard index < imageCards.count, imageCards[index].status == .success,
              let data = imageCards[index].decodedImageData, let ui = UIImage(data: data) else {
            errorMessage = "图片不存在或未生成"; return
        }
        PHPhotoLibrary.requestAuthorization { s in
            guard s == .authorized || s == .limited else { DispatchQueue.main.async { self.errorMessage = "无相册权限" }; return }
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
