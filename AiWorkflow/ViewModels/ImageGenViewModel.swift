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

    // 参考图
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
        self.store = store
        self.imageService = imageService
        self.project = project
        self.useGlobalReferenceImage = project.useGlobalReferenceImage
        self.referenceImageFilePath = project.globalReferenceImageLocalPath
        if let path = project.globalReferenceImageLocalPath {
            self.selectedReferenceImageData = try? Data(contentsOf: URL(fileURLWithPath: path))
        }

        let svcType = "\(type(of: imageService))"
        print("""
        📷 [ImageGen] setup:
           service=\(svcType)
           cards=\(project.imageCards.count)
           useRef=\(project.useGlobalReferenceImage)
           refPath=\(project.globalReferenceImageLocalPath ?? "nil")
        """)
    }

    deinit { currentTask?.cancel() }

    // MARK: - 参考图

    func setReferenceImage(data: Data, filePath: String) {
        selectedReferenceImageData = data
        referenceImageFilePath = filePath
        useGlobalReferenceImage = true
        guard var p = project else { return }
        p.globalReferenceImageLocalPath = filePath
        p.useGlobalReferenceImage = true
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        print("📷 [ImageGen] 参考图已设置: \(filePath)")
    }

    func clearReferenceImage() {
        selectedReferenceImageData = nil
        referenceImageFilePath = nil
        useGlobalReferenceImage = false
        guard var p = project else { return }
        p.globalReferenceImageLocalPath = nil
        p.useGlobalReferenceImage = false
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        print("📷 [ImageGen] 参考图已清除")
    }

    // MARK: - 单张生成

    func generateImage(at index: Int) async {
        let tag = "📷[\(index)]"
        print("\n\(tag) ===== 生成第\(index+1)张 =====")

        // 校验 1: service
        guard let imgSvc = imageService else {
            setCardFailed(index, status: .failed, error: "图片服务未初始化")
            return
        }
        // 校验 2: project
        guard var p = project, index < p.imageCards.count else {
            setCardFailed(index, status: .failed, error: "项目或卡片索引无效")
            return
        }
        // 校验 3: prompt
        let promptText: String
        if index < p.promptCards.count, !p.promptCards[index].promptText.isEmpty {
            promptText = p.promptCards[index].promptText
        } else {
            print("\(tag) ⚠️ promptText 为空，使用默认测试 prompt")
            promptText = "A cute white round-headed cartoon character, dark blue-black background, dual-panel comic, 3:4 ratio"
        }
        let size = p.ratio == "3:4" ? "1024x1792" : "1024x1024"

        // 参考图
        var refBase64: String? = nil
        let refMode: String
        if useGlobalReferenceImage, let data = selectedReferenceImageData {
            refBase64 = data.base64EncodedString()
            refMode = p.globalReferenceImageMode.rawValue
            print("\(tag) 参考图已启用: mode=\(refMode) base64长度=\(refBase64?.count ?? 0)")
        } else {
            refMode = "disabled"
            print("\(tag) 参考图未启用")
        }

        // 标记 generating（所有校验通过后）
        currentGeneratingIndex = index
        p.imageCards[index].status = .generating
        p.imageCards[index].promptText = promptText
        p.imageCards[index].errorMessage = nil
        project = p

        let start = Date()
        do {
            print("\(tag) ⏳ 调用 API... prompt=\(promptText.prefix(200))")
            let results: [ImageGenerationResult]
            if refMode != "disabled", let refB64 = refBase64 {
                results = try await imgSvc.generateImage(
                    prompt: promptText, size: size, n: 1,
                    referenceImageBase64: refB64, referenceMode: refMode
                )
            } else {
                results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1)
            }
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(start)
            print("\(tag) ✅ API 返回 (\(String(format: "%.1f", elapsed))s), results=\(results.count)")

            guard let result = results.first else {
                setCardFailed(index, status: .parseFailed, error: "API 返回空结果")
                currentGeneratingIndex = nil; return
            }

            // 处理结果
            try await processResult(index: index, result: result)

        } catch is CancellationError {
            setCardFailed(index, status: .cancelled, error: "请求被取消")
            currentGeneratingIndex = nil
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                switch ns.code {
                case NSURLErrorCancelled:
                    setCardFailed(index, status: .cancelled, error: "请求被中断（后台）")
                case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
                    setCardFailed(index, status: .failed, error: "图片接口 URL 无效，请在设置中检查")
                case NSURLErrorCannotConnectToHost:
                    setCardFailed(index, status: .failed, error: "无法连接到图片服务器")
                case NSURLErrorTimedOut:
                    setCardFailed(index, status: .failed, error: "图片请求超时")
                default:
                    setCardFailed(index, status: .failed, error: "网络错误: \(error.localizedDescription)")
                }
            } else {
                setCardFailed(index, status: .failed, error: error.localizedDescription)
            }
            currentGeneratingIndex = nil
        }
    }

    private func processResult(index: Int, result: ImageGenerationResult) async throws {
        let tag = "📷[\(index)]"

        if let data = result.imageData, !data.isEmpty {
            print("\(tag) ✅ 获取到图片数据: \(data.count) bytes")
            try await saveImageLocally(index: index, imageData: data, result: result)
            return
        }

        if let urlStr = result.imageURL, let url = URL(string: urlStr) {
            print("\(tag) URL: \(urlStr), 开始下载...")
            do {
                let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 30))
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if !data.isEmpty {
                    print("\(tag) ✅ 下载成功: \(data.count) bytes HTTP \(code)")
                    try await saveImageLocally(index: index, imageData: data, result: result)
                    return
                }
                print("\(tag) ❌ 下载数据为空 HTTP \(code)")
                setCardFailed(index, status: .parseFailed, error: "图片 URL 下载返回空 (HTTP \(code))", rawResponse: urlStr)
            } catch {
                setCardFailed(index, status: .parseFailed, error: "图片下载失败: \(error.localizedDescription)", rawResponse: urlStr)
            }
            currentGeneratingIndex = nil; return
        }

        // 无 data 无 url
        setCardFailed(index, status: .parseFailed, error: "API 返回成功但无法解析图片格式", rawResponse: result.revisedPrompt ?? "无返回数据")
        currentGeneratingIndex = nil
    }

    private func saveImageLocally(index: Int, imageData: Data, result: ImageGenerationResult) async throws {
        let tag = "📷[\(index)]"
        #if os(iOS)
        guard UIImage(data: imageData) != nil else {
            setCardFailed(index, status: .parseFailed, error: "图片数据无法解码为 UIImage")
            return
        }
        #endif

        let fileName = "img_\(project?.id.uuidString.prefix(8) ?? "x")_\(index).jpg"
        guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            setCardFailed(index, status: .saveFailed, error: "无法获取文档目录")
            return
        }
        let fileURL = docDir.appendingPathComponent(fileName)
        do {
            try imageData.write(to: fileURL)
            print("\(tag) ✅ 本地保存: \(fileURL.path)")
        } catch {
            setCardFailed(index, status: .saveFailed, error: "本地保存失败: \(error.localizedDescription)")
            return
        }

        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .success
        p.imageCards[index].imageBase64 = imageData.base64EncodedString()
        p.imageCards[index].localFilePath = fileURL.path
        p.imageCards[index].imageURL = result.imageURL
        p.imageCards[index].rawResponse = result.revisedPrompt ?? ""
        p.imageCards[index].errorMessage = nil
        if p.imageCards.allSatisfy({ $0.status == .success }) { p.status = .imagesReady }
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        currentGeneratingIndex = nil
        print("\(tag) ✅ 完成: \(fileURL.lastPathComponent)")
    }

    private func setCardFailed(_ index: Int, status: ImageStatus, error: String, rawResponse: String = "") {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = status
        p.imageCards[index].errorMessage = error
        if !rawResponse.isEmpty { p.imageCards[index].rawResponse = rawResponse }
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        print("📷[\(index)] ❌ \(status.rawValue): \(error)")
        errorMessage = error
    }

    // MARK: - 测试

    func generateTestImage(at index: Int) {
        print("\n🧪 [ImageGen] 测试第\(index+1)张（固定 prompt）")
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].promptText = "A cute white round-headed cartoon character in dark blue-black room, dual-panel comic, 3:4 ratio"
        project = p; store?.upsert(p)
        Task { await generateImage(at: index); if let np = project { store?.upsert(np) } }
    }

    // MARK: - 批量生成

    func generateAllImages() {
        print("\n🔵 [ImageGen] ===== 批量生成 =====")
        guard let p = project else { errorMessage = "项目未加载"; return }

        let freshProject: Project
        if let s = store, let reloaded = s.project(id: p.id) {
            freshProject = reloaded
            project = reloaded
        } else { freshProject = p }

        let toGenerate = freshProject.imageCards.indices.filter { freshProject.imageCards[$0].status != .success }
        print("🔵 待生成: \(toGenerate.count) 张")
        if toGenerate.isEmpty { return }

        currentTask?.cancel()
        isLoading = true; errorMessage = nil; progressText = ""; currentGeneratingIndex = nil

        var np = freshProject
        for idx in toGenerate { np.imageCards[idx].status = .idle; np.imageCards[idx].errorMessage = nil }
        project = np; store?.upsert(np)

        currentTask = Task {
            for (loopIdx, idx) in toGenerate.enumerated() {
                if Task.isCancelled { break }
                progressText = "生成第\(loopIdx+1)/\(toGenerate.count)张..."
                await generateImage(at: idx)
                if let np2 = project { store?.upsert(np2) }
            }
            isLoading = false; currentGeneratingIndex = nil
            let done = successCount; let total = imageCards.count
            progressText = done == total ? "全部完成" : "\(done)/\(total) 张完成"
            print("🔵 [ImageGen] 批量完成: \(done)/\(total)")
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
        guard var p = project else { return }
        p.status = .completed; p.updatedAt = Date()
        store?.upsert(p); project = p
    }
}
