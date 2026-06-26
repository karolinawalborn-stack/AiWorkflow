import SwiftUI

struct ImageGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.imageService) private var imageService
    @StateObject private var vm = ImageGenViewModel()
    @State private var showImagePicker = false
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 4, total: 4, tint: .green) }

                    // ── 参考图模块 ──
                    referenceImageView

                    // ── 操作按钮 ──
                    HStack(spacing: 12) {
                        Button { vm.generateAllImages() } label: {
                            HStack { Image(systemName: "photo.on.rectangle.angled"); Text(vm.isLoading ? "生成中..." : "全部生成") }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                        if vm.allSuccess { Button("完成") { vm.completeProject() }.buttonStyle(.bordered) }
                    if vm.successCount > 0 { Button("下载到相册") { vm.downloadAllToAlbum() }.buttonStyle(.bordered).tint(.green) }
                    }

                    // 调试按钮
                    HStack(spacing: 12) {
                        Button { vm.generateTestImage(at: 0) } label: {
                            HStack { Image(systemName: "ladybug"); Text("测试第1张（固定 prompt）").font(.caption) }.frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(.orange).disabled(vm.isLoading)
                    }

                    // ── 顶部统计 ──
                    statsView

                    // ── 错误提示 ──
                    if let err = vm.errorMessage {
                        Text(err).font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ── 图片卡片 ──
                    if !vm.imageCards.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(vm.imageCards) { card in
                                ImageCardDebugView(
                                    card: card,
                                    isGenerating: vm.currentGeneratingIndex == card.cardIndex,
                                    hasReference: vm.useGlobalReferenceImage,
                                    onGenerate: { Task { await vm.generateImage(at: card.cardIndex) } },
                                    onRegenerate: { vm.regenerateImage(at: card.cardIndex) },
                                    onSaveToAlbum: { vm.saveToAlbum(at: card.cardIndex) }
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 12) { Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary); Text("暂无图片").foregroundColor(.secondary) }.padding(.vertical, 40)
                    }
                }.padding()
            }

            // ── 底部 ──
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("\(vm.successCount)/\(vm.imageCards.count) 张").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if let m = vm.exportMessage { Text(m).font(.caption).foregroundColor(.green) }
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("出图").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { data, url in
                if let d = data, let u = url {
                    vm.setReferenceImage(data: d, filePath: u.path)
                }
            }
        }
        .onAppear {
            if let p = store.project(id: projectID) {
                vm.setup(store: store, imageService: imageService, project: p)
            }
        }
    }

    // MARK: - 参考图

    private var referenceImageView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle").foregroundColor(.blue)
                Text("参考图").font(.subheadline.bold())
                Spacer()
                if vm.useGlobalReferenceImage {
                    Text("已启用").font(.caption2).foregroundColor(.green).padding(.horizontal, 8).padding(.vertical, 2).background(Color.green.opacity(0.1)).cornerRadius(4)
                }
            }

            if let refs = vm.project?.referenceImages, !refs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(refs) { ref in
                            if let d = try? Data(contentsOf: URL(fileURLWithPath: ref.localFilePath)), let ui = UIImage(data: d) {
                                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit).frame(width: 50, height: 66).cornerRadius(4)
                                    .overlay(alignment: .topTrailing) {
                                        Button { vm.clearReferenceImage() } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.red).background(Color.white.clipShape(Circle())) }.buttonStyle(.plain).offset(x: 4, y: -4)
                                    }
                            }
                        }
                    }
                }.frame(height: 70)
            } else if let data = vm.selectedReferenceImageData, let ui = UIImage(data: data) {
                HStack(spacing: 12) {
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit).frame(width: 60, height: 80).cornerRadius(6)
                    VStack(alignment: .leading, spacing: 4) {
                        let refCount = vm.project?.referenceImages.count ?? (vm.selectedReferenceImageData != nil ? 1 : 0)
                        Text("参考图已选择 (\(refCount)张)").font(.caption).foregroundColor(.secondary)
                        Text("模式: \(projectRefModeDisplay)").font(.caption2).foregroundColor(.secondary)
                        if vm.project?.globalReferenceImageMode == .promptOnlyFallback {
                            Text("当前接口未确认支持真实图片输入，已降级为「风格参考模式」").font(.caption2).foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    Button("清除") { vm.clearReferenceImage() }.font(.caption).buttonStyle(.bordered).tint(.red)
                }
                .padding(8).background(Color(.systemGray6)).cornerRadius(8)
            } else {
                Button { showImagePicker = true } label: {
                    HStack { Image(systemName: "plus.circle"); Text("从相册选择参考图").font(.subheadline) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.bordered)
            }
        }
        .padding(12).background(Color.blue.opacity(0.03)).cornerRadius(12)
    }

    private var projectRefModeDisplay: String {
        vm.project?.globalReferenceImageMode.displayName ?? "未设置"
    }

    // MARK: - 统计

    private var statsView: some View {
        let total = vm.imageCards.count
        let done = vm.successCount
        return HStack {
            if vm.allSuccess {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("全部完成（\(done)/\(total)）").font(.caption).foregroundColor(.green)
            } else if done > 0 {
                Image(systemName: "ellipsis.circle").foregroundColor(.orange)
                Text("\(done)/\(total) 张成功").font(.caption).foregroundColor(.orange)
            } else {
                Image(systemName: "photo").foregroundColor(.secondary)
                Text("点击「全部生成」或「测试」开始").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6)).cornerRadius(8)
    }
}

// MARK: - 图片卡片（带调试面板）

struct ImageCardDebugView: View {
    let card: ImageCard
    let isGenerating: Bool
    let hasReference: Bool
    let onGenerate: () -> Void
    let onRegenerate: () -> Void
    let onSaveToAlbum: () -> Void

    @State private var showDebug = false

    var body: some View {
        VStack(spacing: 8) {
            // ── 图片 ──
            ZStack {
                if let data = card.decodedImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().aspectRatio(3/4, contentMode: .fit).cornerRadius(8)
                } else {
                    Rectangle().aspectRatio(3/4, contentMode: .fit).foregroundColor(bgColor).cornerRadius(8)
                        .overlay { statusOverlay }
                }
                if card.status == .success {
                    VStack { HStack { Spacer(); Text("图\(card.cardIndex+1)").font(.caption2).padding(.horizontal,6).padding(.vertical,3).background(Color.black.opacity(0.6)).foregroundColor(.white).cornerRadius(4).padding(4) }; Spacer() }
                }
            }

            // ── 状态 ──
            Text(statusLabel).font(.caption2).foregroundColor(statusColor)

            // ── 按钮 ──
            HStack(spacing: 8) {
                if card.status == .success {
                    Button(action: onSaveToAlbum) { Image(systemName: "square.and.arrow.down").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                    Button(action: onRegenerate) { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                } else if card.status == .idle || card.status == .failed || card.status == .parseFailed || card.status == .saveFailed || card.status == .cancelled {
                    Button(action: onGenerate) {
                        HStack { Image(systemName: "wand.and.stars"); Text(card.status == .idle ? "生成" : "重试").font(.caption) }.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.small).disabled(isGenerating)
                } else if isGenerating {
                    ProgressView().scaleEffect(0.7)
                }
            }

            // ── 调试面板 ──
            if showDebugToggle {
                Button { withAnimation { showDebug.toggle() } } label: {
                    HStack { Image(systemName: showDebug ? "chevron.down" : "chevron.right"); Text("调试信息").font(.caption2) }.foregroundColor(.secondary)
                }
                if showDebug { debugPanel }
            }
        }
        .padding(8).background(cardBackground).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: isGenerating ? 2 : 0.5))
    }

    private var showDebugToggle: Bool {
        card.status == .failed || card.status == .parseFailed || card.status == .saveFailed || card.status == .cancelled || card.status == .success || !card.rawResponse.isEmpty || card.errorMessage != nil
    }

    @ViewBuilder
    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let err = card.errorMessage { Text("错误: \(err)").font(.system(size: 9)).foregroundColor(.red) }
            Text("状态: \(card.status.rawValue)").font(.system(size: 9)).foregroundColor(.secondary)
            if hasReference { Text("参考图: 已启用").font(.system(size: 9)).foregroundColor(.blue) }
            Text("prompt前200: \(card.promptText.prefix(200))").font(.system(size: 8)).foregroundColor(.secondary)
            if let path = card.localFilePath { Text("路径: \(path)").font(.system(size: 8)).foregroundColor(.secondary) }
            if !card.rawResponse.isEmpty {
                Text("原始响应:").font(.system(size: 8)).foregroundColor(.secondary)
                Text(card.rawResponse).font(.system(size: 7, design: .monospaced)).foregroundColor(.secondary).lineLimit(8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(6).background(Color(.systemGray6)).cornerRadius(6)
    }

    // MARK: - 状态衍生

    private var statusLabel: String {
        switch card.status {
        case .idle:        return "等待生成"
        case .generating:  return "生成中..."
        case .success:     return "✅ 成功"
        case .failed:      return "❌ 请求失败"
        case .parseFailed: return "⚠️ 格式未适配"
        case .binaryImageReceived: return "📷 已收到图片"
        case .taskAccepted: return "⏳ 任务已接收"
        case .polling:     return "🔄 轮询中"
        case .saveFailed:  return "⚠️ 保存失败"
        case .timeout:     return "⏰ 查询超时"
        case .cancelled:   return "🚫 已取消"
        }
    }

    private var statusColor: Color {
        switch card.status {
        case .idle:        return .secondary
        case .generating:  return .orange
        case .success:     return .green
        case .failed:      return .red
        case .parseFailed: return .orange
        case .binaryImageReceived: return .blue
        case .taskAccepted: return .purple
        case .polling:     return .orange
        case .timeout:     return .red
        case .saveFailed:  return .orange
        case .cancelled:   return .gray
        }
    }

    private var bgColor: Color {
        switch card.status {
        case .failed, .cancelled: return Color.red.opacity(0.08)
        case .parseFailed: return Color.orange.opacity(0.08)
        case .success: return Color(.systemGray5)
        default: return Color(.systemGray5)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isGenerating {
            VStack(spacing: 8) { ProgressView(); Text("生成中...").font(.caption) }.foregroundColor(.secondary)
        } else if card.status == .failed || card.status == .cancelled {
            VStack(spacing: 4) { Image(systemName: "xmark.circle").font(.title2); Text(statusLabel).font(.caption2); if let e = card.errorMessage { Text(e).font(.caption2).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center) } }.foregroundColor(statusColor).padding(8)
        } else if card.status == .parseFailed || card.status == .saveFailed {
            VStack(spacing: 4) { Image(systemName: "exclamationmark.triangle").font(.title2); Text(statusLabel).font(.caption2); if let e = card.errorMessage { Text(e).font(.caption2).foregroundColor(.secondary).lineLimit(3).multilineTextAlignment(.center) } }.foregroundColor(statusColor).padding(8)
        } else if card.status == .idle {
            VStack(spacing: 4) { Image(systemName: "photo").font(.title2); Text("未生成").font(.caption) }.foregroundColor(.secondary)
        }
    }

    private var cardBackground: Color {
        if card.status == .success { return Color.green.opacity(0.04) }
        if card.status == .failed || card.status == .cancelled { return Color.red.opacity(0.03) }
        return Color(.systemGray6)
    }

    private var borderColor: Color {
        if isGenerating { return Color.orange.opacity(0.5) }
        if card.status == .success { return Color.green.opacity(0.2) }
        return Color.clear
    }
}

// MARK: - 图片选择器（简化版）

#if canImport(UIKit)
import UIKit

struct ImagePickerView: UIViewControllerRepresentable {
    let onComplete: (Data?, URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ ui: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (Data?, URL?) -> Void
        init(onComplete: @escaping (Data?, URL?) -> Void) { self.onComplete = onComplete }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let url = info[.imageURL] as? URL
            let data = (info[.originalImage] as? UIImage).flatMap { $0.jpegData(compressionQuality: 0.8) }
            onComplete(data, url)
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil, nil)
            picker.dismiss(animated: true)
        }
    }
}

#endif
