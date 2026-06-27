import SwiftUI

struct PromptGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = PromptViewModel()
    @State private var goNext = false
    @State private var showBatchImport = false
@State private var batchText: String = ""
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 3, total: 4, tint: .orange) }

                    HStack(spacing: 12) {
                        Button { vm.generatePrompts() } label: {
                            HStack { Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "生成提示词") }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                        if vm.nonEmptyPromptCount > 0 { Button("批量复制") { vm.copyAllPrompts() }.buttonStyle(.bordered)
                            Button("批量导入") { showBatchImport = true }.buttonStyle(.bordered) }
                    }

                    // ── 顶部统计 ──
                    let total = vm.prompts.count
                    let done = vm.nonEmptyPromptCount
                    HStack {
                        if done == total && total > 0 {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("全部完成（\(done)/\(total)）").font(.caption).foregroundColor(.green)
                        } else if done > 0 {
                            Image(systemName: "ellipsis.circle").foregroundColor(.orange)
                            Text("\(done)/\(total) 条有内容").font(.caption).foregroundColor(.orange)
                        } else if vm.isLoading {
                            ProgressView().scaleEffect(0.7)
                            Text("生成中...").font(.caption).foregroundColor(.secondary)
                        } else {
                            Image(systemName: "doc.text.magnifyingglass").foregroundColor(.secondary)
                            Text("点击生成提示词").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6)).cornerRadius(8)

                    if vm.isLoading {
                        VStack(spacing: 12) { ProgressView(); Text("正在逐张生成提示词...").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if !vm.prompts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("提示词列表").font(.subheadline.bold())
                            ForEach(vm.prompts) { pr in
                                PromptEditorView(
                                    text: pr.promptText,
                                    index: pr.cardIndex,
                                    isGenerating: vm.currentGeneratingIndex == pr.cardIndex,
                                    onEdit: { pr2 in vm.updatePrompt(at: pr.cardIndex, prompt: pr2, description: "") },
                                    onCopy: { vm.copyPrompt(at: pr.cardIndex) }
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundColor(.secondary)
                            Text("点击「生成提示词」开始").foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }.padding()
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("保存为模板") { vm.saveAsTemplate() }.buttonStyle(.bordered)
                    Spacer()
                    Button("下一步：出图") { goNext = true }.buttonStyle(.borderedProminent)
                        .disabled(vm.nonEmptyPromptCount == 0)
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("生图提示词").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) { ImageGenView(projectID: projectID) }
        .overlay(alignment: .top) {
            if vm.lastCopied != nil {
                Text("已复制").font(.caption).padding(.horizontal, 16).padding(.vertical, 8).background(Color.green).foregroundColor(.white).cornerRadius(20).padding(.top, 8)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now()+2) { withAnimation { vm.lastCopied = nil } } }
            }
        }
        .sheet(isPresented: $showBatchImport) {
            PromptBatchImportView(text: $batchText, onImport: { vm.batchImportPrompts($0); showBatchImport = false; batchText = "" }, onCancel: { showBatchImport = false; batchText = "" })
        }
        .onChange(of: vm.lastCopied) { _ in DispatchQueue.main.asyncAfter(deadline: .now()+2) { withAnimation { vm.lastCopied = nil } } }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }
}

// MARK: - 单张提示词卡片行

struct PromptCardRow: View {
    let card: PromptCard
    let isGenerating: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── 头部：序号 + 状态 ──
            HStack {
                Text("图\(card.cardIndex+1)").font(.caption).fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor).cornerRadius(6)

                Spacer()

                // 状态文本
                Text(statusText).font(.caption2).foregroundColor(statusColor)

                if !card.promptText.isEmpty {
                    Button(action: onCopy) { Image(systemName: "doc.on.doc").font(.caption) }.buttonStyle(.plain)
                }
                if card.status == .success || card.status == .failed {
                    Button(action: onRegenerate) { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.plain)
                }
            }

            // ── 内容区 ──
            if isGenerating {
                HStack { ProgressView().scaleEffect(0.8); Text("生成中...").font(.caption).foregroundColor(.secondary) }.padding(.vertical, 8)
            } else if card.status == .success && !card.promptText.isEmpty {
                Text(card.promptText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(10)
            } else if card.status == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("（生成失败）").font(.caption).foregroundColor(.red)
                    if let err = card.errorMessage { Text(err).font(.caption2).foregroundColor(.secondary) }
                }
            } else if card.status == .pending {
                Text("（等待生成）").font(.caption).foregroundColor(.secondary)
            }

            // ── 原始响应调试区（每张卡片自带） ──
            if !card.rawResponse.isEmpty && card.rawResponse != card.promptText {
                Button { withAnimation { showRaw.toggle() } } label: {
                    HStack { Image(systemName: showRaw ? "chevron.down" : "chevron.right"); Text("原始响应 (\(card.rawResponse.count)字符)").font(.caption2) }.foregroundColor(.secondary)
                }
                if showRaw {
                    Text(card.rawResponse).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        .background(Color(.systemGray6)).cornerRadius(6)
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: isGenerating ? 1.5 : 0.5))
    }

    // MARK: - 状态衍生属性

    private var statusText: String {
        switch card.status {
        case .pending:   return "等待生成"
        case .generating: return "生成中..."
        case .success:   return "✅ 已生成"
        case .failed:    return "❌ 失败"
        }
    }

    private var statusColor: Color {
        switch card.status {
        case .pending:    return .secondary
        case .generating: return .orange
        case .success:    return .green
        case .failed:     return .red
        }
    }

    private var cardBackground: Color {
        card.status == .success ? Color.green.opacity(0.04) : Color(.systemGray6)
    }

    private var borderColor: Color {
        isGenerating ? Color.orange.opacity(0.5) : Color.clear
    }
}
