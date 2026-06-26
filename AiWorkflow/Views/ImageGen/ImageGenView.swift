import SwiftUI

struct ImageGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.imageService) private var imageService
    @StateObject private var vm = ImageGenViewModel()
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 4, total: 4, tint: .green) }

                    HStack(spacing: 12) {
                        Button { vm.generateAllImages() } label: {
                            HStack { Image(systemName: "photo.on.rectangle.angled"); Text(vm.isLoading ? "生成中..." : "全部生成") }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                        if vm.allSuccess { Button("完成") { vm.completeProject() }.buttonStyle(.bordered) }
                    }

                    // ── 测试按钮（固定 prompt，不依赖 promptCards） ──
                    Button {
                        print("\n🧪 [UI] 测试第1张出图请求 — 使用固定 prompt")
                        vm.generateTestImage(at: 0)
                    } label: {
                        HStack { Image(systemName: "ladybug"); Text("测试第1张出图（固定 prompt）").font(.caption) }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(.orange).disabled(vm.isLoading)

                    // ── 顶部统计 ──
                    let total = vm.imageCards.count
                    let done = vm.successCount
                    HStack {
                        if vm.allSuccess {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("全部完成（\(done)/\(total)）").font(.caption).foregroundColor(.green)
                        } else if done > 0 {
                            Image(systemName: "ellipsis.circle").foregroundColor(.orange)
                            Text("\(done)/\(total) 张成功").font(.caption).foregroundColor(.orange)
                        } else if vm.errorMessage != nil {
                            Image(systemName: "exclamationmark.circle").foregroundColor(.red)
                            Text("有错误").font(.caption).foregroundColor(.red)
                        } else {
                            Image(systemName: "photo").foregroundColor(.secondary)
                            Text("点击「全部生成」开始").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6)).cornerRadius(8)

                    // 全局错误提示
                    if let err = vm.errorMessage {
                        Text(err).font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ── 图片卡片列表 ──
                    if !vm.imageCards.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(vm.imageCards) { card in
                                ImageCardView(
                                    card: card,
                                    isGenerating: vm.currentGeneratingIndex == card.cardIndex,
                                    onGenerate: { Task { await vm.generateImage(at: card.cardIndex) } },
                                    onRegenerate: { vm.regenerateImage(at: card.cardIndex) },
                                    onSaveToAlbum: { vm.saveToAlbum(at: card.cardIndex) }
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary)
                            Text("暂无图片").foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }.padding()
            }

            // ── 底部状态栏 ──
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("\(vm.successCount)/\(vm.imageCards.count) 张").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if let m = vm.exportMessage {
                        Text(m).font(.caption).foregroundColor(.green)
                    }
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("出图").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let p = store.project(id: projectID) {
                vm.setup(store: store, imageService: imageService, project: p)
            }
        }
    }
}

// MARK: - 单张图片卡片

struct ImageCardView: View {
    let card: ImageCard
    let isGenerating: Bool
    let onGenerate: () -> Void
    let onRegenerate: () -> Void
    let onSaveToAlbum: () -> Void

    @State private var showDebug = false

    var body: some View {
        VStack(spacing: 8) {
            // ── 图片区 ──
            ZStack {
                if let data = card.decodedImageData, let ui = UIImage(data: data) {
                    // 成功显示图片
                    Image(uiImage: ui).resizable().aspectRatio(3/4, contentMode: .fit).cornerRadius(8)
                } else {
                    // 占位图
                    Rectangle().aspectRatio(3/4, contentMode: .fit).foregroundColor(placeholderColor).cornerRadius(8)
                        .overlay { statusOverlay }
                }
                // 角标
                if card.status == .success {
                    VStack { HStack { Spacer(); Text("图\(card.cardIndex+1)").font(.caption2).padding(.horizontal,6).padding(.vertical,3).background(Color.black.opacity(0.6)).foregroundColor(.white).cornerRadius(4).padding(4) }; Spacer() }
                }
            }

            // ── 状态标签 ──
            Text(statusLabel).font(.caption2).foregroundColor(statusColor)

            // ── 操作按钮 ──
            HStack(spacing: 8) {
                if card.status == .success {
                    Button(action: onSaveToAlbum) { Image(systemName: "square.and.arrow.down").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                    Button(action: onRegenerate) { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.bordered).controlSize(.small)
                } else if card.status == .idle || card.status == .failed || card.status == .parseFailed || card.status == .saveFailed {
                    Button(action: onGenerate) {
                        HStack { Image(systemName: "wand.and.stars"); Text(card.status == .idle ? "生成" : "重试").font(.caption) }.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.small).disabled(isGenerating)
                } else if isGenerating {
                    ProgressView().scaleEffect(0.7)
                    Text("生成中...").font(.caption2).foregroundColor(.secondary)
                }
            }

            // ── 调试信息 ──
            if card.status == .failed || card.status == .parseFailed || card.status == .saveFailed || !card.rawResponse.isEmpty {
                Button { withAnimation { showDebug.toggle() } } label: {
                    HStack { Image(systemName: showDebug ? "chevron.down" : "chevron.right"); Text("调试信息").font(.caption2) }.foregroundColor(.secondary)
                }
                if showDebug {
                    VStack(alignment: .leading, spacing: 4) {
                        if let err = card.errorMessage { Text("错误: \(err)").font(.system(size: 9)).foregroundColor(.red) }
                        if let path = card.localFilePath { Text("路径: \(path)").font(.system(size: 9)).foregroundColor(.secondary) }
                        if card.status == .success { Text("状态: 成功 ✓").font(.system(size: 9)).foregroundColor(.green) }
                        if !card.rawResponse.isEmpty {
                            Text("原始响应:").font(.system(size: 9)).foregroundColor(.secondary)
                            Text(card.rawResponse).font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary).lineLimit(6)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6).background(Color(.systemGray6)).cornerRadius(6)
                }
            }
        }
        .padding(8)
        .background(cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: isGenerating ? 2 : 0.5))
    }

    // MARK: - 状态衍生

    private var statusLabel: String {
        switch card.status {
        case .idle:        return "等待生成"
        case .generating:  return "生成中..."
        case .success:     return "✅ 成功"
        case .failed:      return "❌ 请求失败"
        case .parseFailed: return "⚠️ 解析失败"
        case .saveFailed:  return "⚠️ 保存失败"
        }
    }

    private var statusColor: Color {
        switch card.status {
        case .idle:        return .secondary
        case .generating:  return .orange
        case .success:     return .green
        case .failed:      return .red
        case .parseFailed: return .orange
        case .saveFailed:  return .orange
        }
    }

    private var placeholderColor: Color {
        switch card.status {
        case .idle:        return Color(.systemGray5)
        case .generating:  return Color(.systemGray4)
        case .success:     return Color(.systemGray5)
        case .failed:      return Color.red.opacity(0.1)
        case .parseFailed: return Color.orange.opacity(0.1)
        case .saveFailed:  return Color.orange.opacity(0.1)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isGenerating {
            VStack(spacing: 8) { ProgressView(); Text("生成中...").font(.caption) }.foregroundColor(.secondary)
        } else if card.status == .failed || card.status == .parseFailed || card.status == .saveFailed {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle").font(.title2)
                Text(statusLabel).font(.caption2).multilineTextAlignment(.center)
                if let err = card.errorMessage { Text(err).font(.caption2).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center) }
            }.foregroundColor(statusColor).padding(8)
        } else if card.status == .idle {
            VStack(spacing: 4) { Image(systemName: "photo").font(.title2); Text("未生成").font(.caption) }.foregroundColor(.secondary)
        }
    }

    private var cardBackground: Color {
        if card.status == .success { return Color.green.opacity(0.04) }
        if card.status == .failed || card.status == .parseFailed { return Color.red.opacity(0.03) }
        return Color(.systemGray6)
    }

    private var borderColor: Color {
        if isGenerating { return Color.orange.opacity(0.5) }
        if card.status == .success { return Color.green.opacity(0.2) }
        return Color.clear
    }
}
