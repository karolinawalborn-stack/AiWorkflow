import SwiftUI
#if os(iOS)
import UIKit
import Photos
#endif

///
/// 图片生成 ViewModel — 单一数据源 + 逐张生成 + 多格式适配
///
@MainActor
final class ImageGenViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var progressText: String = ""
    @Published var errorMessage: String?
    @Published var exportMessage: String?

    /// 当前正在生成的卡片 index
    @Published var currentGeneratingIndex: Int? = nil

    @Published var project: Project?
    private var store: ProjectStore?
    private var imageService: AIImageServiceProtocol?
    private var currentTask: Task<Void, Never>?

    // MARK: - 单一数据源

    /// 图片卡片列表（从 project 直接读取）
    var imageCards: [ImageCard] {
        project?.sortedImages ?? []
    }

    /// 成功生成的张数
    var successCount: Int {
        imageCards.filter { $0.status == .success }.count
    }

    /// 全部生成完毕
    var allSuccess: Bool {
        !imageCards.isEmpty && imageCards.allSatisfy { $0.status == .success }
    }

    // MARK: - 设置

    func setup(store: ProjectStore, imageService: AIImageServiceProtocol, project: Project) {
        self.store = store
        self.imageService = imageService
        self.project = project

        let success = project.sortedImages.filter { $0.status == .success }.count
        let failed = project.sortedImages.filter { $0.status == .failed || $0.status == .parseFailed || $0.status == .saveFailed }.count
        print("""
        📷 [ImageGen] setup:
           imageCards=\(project.imageCards.count) 张
           成功=\(success) | 失败=\(failed) | 待生成=\(project.imageCards.count - success - failed)
           promptCards 非空=\(project.promptCards.filter { !$0.promptText.isEmpty }.count)
        """)
        for (i, c) in project.sortedCopyCards.enumerated() {
            print("   copy[\(i)] bottom=「\(c.bottomText.prefix(20))」")
        }
        for (i, p) in project.sortedPrompts.enumerated() {
            print("   prompt[\(i)] status=\(p.status.rawValue) text=「\(p.promptText.prefix(30))」")
        }
        for (i, img) in project.sortedImages.enumerated() {
            print("   image[\(i)] status=\(img.status.rawValue) hasLocal=\(img.localFilePath != nil)")
        }
    }

    deinit {
        currentTask?.cancel()
    }

    // MARK: - 单张生成

    /// 生成第 N 张图片
    func generateImage(at index: Int) async {
        print("\n========== 📷 [ImageGen] 第\(index+1)张 ==========")
        guard index >= 0 else { return }
        guard let imgSvc = imageService else { errorMessage = "图片服务未初始化"; return }
        guard var p = project, index < p.imageCards.count else { errorMessage = "索引越界"; return }

        // 获取提示词
        let promptText: String
        if index < p.promptCards.count, !p.promptCards[index].promptText.isEmpty {
            promptText = p.promptCards[index].promptText
        } else {
            print("⚠️ [ImageGen] 第\(index+1)张无提示词，使用默认")
            promptText = "A cute white round-headed cartoon character, dark blue-black background, dual-panel comic layout with captions, oppressive emotional atmosphere, 3:4 ratio"
        }
        print("📝 [ImageGen] 使用的 promptText 前300字: \(promptText.prefix(300))")

        let size = p.ratio == "3:4" ? "1024x1792" : "1024x1024"

        // 标记生成中
        currentGeneratingIndex = index
        p.imageCards[index].status = .generating
        p.imageCards[index].promptText = promptText
        p.imageCards[index].errorMessage = nil
        project = p

        let start = Date()

        do {
            let results = try await imgSvc.generateImage(prompt: promptText, size: size, n: 1)
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(start)
            print("✅ [ImageGen] 第\(index+1)张 API 返回 (\(String(format: "%.1f", elapsed))s), results.count=\(results.count)")

            guard let result = results.first else {
                print("❌ [ImageGen] 第\(index+1)张: API 返回空结果")
                setImageFailed(index, status: .parseFailed, error: "API 返回空结果", rawResponse: "")
                currentGeneratingIndex = nil
                return
            }

            // 解析结果
            try await processImageResult(index: index, result: result, size: size)

        } catch is CancellationError {
            print("⏹ [ImageGen] 第\(index+1)张被取消")
            setImageFailed(index, status: .failed, error: "请求被取消")
            currentGeneratingIndex = nil
        } catch {
            print("❌ [ImageGen] 第\(index+1)张失败: \(error.localizedDescription)")
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                setImageFailed(index, status: .failed, error: "请求被中断（后台）")
            } else {
                setImageFailed(index, status: .failed, error: error.localizedDescription)
            }
            currentGeneratingIndex = nil
        }
    }

    /// 处理图片服务返回的结果
    private func processImageResult(index: Int, result: ImageGenerationResult, size: String) async throws {
        print("📥 [ImageGen] 第\(index+1)张 解析结果:")

        // 方案一：有二进制数据 → 保存本地
        if let imageData = result.imageData, !imageData.isEmpty {
            print("   ✔ 获取到二进制数据: \(imageData.count) bytes")
            try await saveImageLocally(index: index, imageData: imageData, result: result, size: size)
            return
        }

        // 方案二：有 URL → 下载
        if let urlStr = result.imageURL, let url = URL(string: urlStr) {
            print("   ✔ 获取到 URL: \(urlStr)")
            print("   ⏳ 开始下载图片...")
            do {
                let request = URLRequest(url: url, timeoutInterval: 30)
                let (data, resp) = try await URLSession.shared.data(for: request)
                guard !data.isEmpty else {
                    print("   ❌ 下载成功但数据为空")
                    setImageFailed(index, status: .parseFailed, error: "图片 URL 下载返回空数据", rawResponse: urlStr)
                    currentGeneratingIndex = nil
                    return
                }
                print("   ✔ URL 下载成功: \(data.count) bytes, resp=\((resp as? HTTPURLResponse)?.statusCode ?? 0)")
                try await saveImageLocally(index: index, imageData: data, result: result, size: size)
            } catch {
                print("   ❌ URL 下载失败: \(error.localizedDescription)")
                setImageFailed(index, status: .parseFailed, error: "图片 URL 下载失败: \(error.localizedDescription)", rawResponse: urlStr)
                currentGeneratingIndex = nil
            }
            return
        }

        // 方案三：都没有 → 标记解析失败
        print("   ❌ 无法识别图片返回格式: 无 data 无 url")
        setImageFailed(index, status: .parseFailed, error: "API 返回成功但无法识别图片数据格式", rawResponse: result.revisedPrompt ?? "未知格式")
        currentGeneratingIndex = nil
    }

    /// 保存图片到本地并更新卡片状态
    private func saveImageLocally(index: Int, imageData: Data, result: ImageGenerationResult, size: String) async throws {
        // 验证图片数据
        #if os(iOS)
        guard UIImage(data: imageData) != nil else {
            print("   ❌ 图片数据无法解码为 UIImage")
            setImageFailed(index, status: .parseFailed, error: "图片数据格式无效，无法解码")
            currentGeneratingIndex = nil
            return
        }
        #endif

        // 保存到本地文件
        let fileName = "img_\(project?.id.uuidString.prefix(8) ?? "unknown")_\(index).jpg"
        let fileURL: URL

        if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            fileURL = docDir.appendingPathComponent(fileName)
            try imageData.write(to: fileURL)
            print("   ✔ 本地保存成功: \(fileURL.path)")
        } else {
            print("   ❌ 无法获取文档目录")
            setImageFailed(index, status: .saveFailed, error: "无法获取文档目录")
            currentGeneratingIndex = nil
            return
        }

        // 更新卡片状态
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = .success
        p.imageCards[index].imageBase64 = imageData.base64EncodedString()
        p.imageCards[index].localFilePath = fileURL.path
        p.imageCards[index].imageURL = result.imageURL
        p.imageCards[index].rawResponse = result.revisedPrompt ?? ""
        p.imageCards[index].errorMessage = nil

        // 全部完成则更新项目状态
        if p.imageCards.allSatisfy({ $0.status == .success }) {
            p.status = .imagesReady
        }
        p.updatedAt = Date()
        store?.upsert(p)
        project = p

        currentGeneratingIndex = nil
        print("✅ [ImageGen] 第\(index+1)张全部完成，已保存到: \(fileURL.lastPathComponent)")
    }

    /// 设置卡片失败状态
    private func setImageFailed(_ index: Int, status: ImageStatus, error: String, rawResponse: String = "") {
        guard var p = project, index < p.imageCards.count else { return }
        p.imageCards[index].status = status
        p.imageCards[index].errorMessage = error
        if !rawResponse.isEmpty { p.imageCards[index].rawResponse = rawResponse }
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        print("❌ [ImageGen] 第\(index+1)张 状态=\(status.rawValue) 错误=\(error)")
    }

    // MARK: - 批量生成

    func generateAllImages() {
        print("🔵 [ImageGen] ===== 开始批量生成 =====")
        guard let p = project else { errorMessage = "项目未加载"; return }

        // 重载项目
        let freshProject: Project
        if let s = store, let reloaded = s.project(id: p.id) {
            freshProject = reloaded
            project = reloaded
        } else {
            freshProject = p
        }

        let toGenerate = freshProject.imageCards.indices.filter { idx in
            freshProject.imageCards[idx].status != .success
        }

        if toGenerate.isEmpty {
            print("✅ [ImageGen] 所有图片已生成")
            return
        }

        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        progressText = ""
        currentGeneratingIndex = nil

        // 重置待生成卡片
        var np = freshProject
        for idx in toGenerate where idx < np.imageCards.count {
            np.imageCards[idx].status = .idle
            np.imageCards[idx].errorMessage = nil
        }
        project = np
        store?.upsert(np)

        currentTask = Task {
            for (loopIdx, idx) in toGenerate.enumerated() {
                if Task.isCancelled { break }
                progressText = "生成第\(loopIdx+1)/\(toGenerate.count)张..."
                await generateImage(at: idx)
                if let np2 = project { store?.upsert(np2) }
            }
            isLoading = false
            currentGeneratingIndex = nil
            let total = imageCards.count
            let done = successCount
            progressText = done == total ? "全部完成" : "\(done)/\(total) 张完成"
            print("✅ [ImageGen] 批量完成: \(done)/\(total)")
        }
    }

    // MARK: - 重新生成单张

    func regenerateImage(at index: Int) {
        guard let p = project, index < p.imageCards.count else { return }

        var np = p
        np.imageCards[index].status = .idle
        np.imageCards[index].errorMessage = nil
        np.imageCards[index].imageBase64 = nil
        np.imageCards[index].localFilePath = nil
        project = np
        store?.upsert(np)

        Task {
            await generateImage(at: index)
            if let np2 = project { store?.upsert(np2) }
        }
    }

    // MARK: - 保存到相册

    func saveToAlbum(at index: Int) {
        #if os(iOS)
        guard index < imageCards.count, imageCards[index].status == .success,
              let data = imageCards[index].decodedImageData,
              let ui = UIImage(data: data) else {
            errorMessage = "图片不存在或未生成"
            return
        }
        PHPhotoLibrary.requestAuthorization { s in
            guard s == .authorized || s == .limited else {
                DispatchQueue.main.async { self.errorMessage = "无相册权限" }
                return
            }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: ui) } completionHandler: { ok, err in
                DispatchQueue.main.async {
                    if ok { self.exportMessage = "已保存" }
                    else { self.errorMessage = "保存失败: \(err?.localizedDescription ?? "")" }
                }
            }
        }
        #endif
    }

    func completeProject() {
        guard var p = project else { return }
        p.status = .completed
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
    }
}
