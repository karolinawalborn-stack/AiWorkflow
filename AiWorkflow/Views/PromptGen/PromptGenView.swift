import SwiftUI

struct PromptGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = PromptViewModel()
    @State private var goNext = false
    @State private var showRawGlobal = false
    @State private var showBatchImport = false
    @State private var batchText: String = ""
    @State private var editingCardIndex: Int? = nil
    @State private var editText: String = ""
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
                        if vm.nonEmptyPromptCount > 0 { Button("批量复制") { vm.copyAllPrompts() }.buttonStyle(.bordered) }
                        Button("批量导入") { showBatchImport = true }.buttonStyle(.bordered).tint(.blue)
                    }

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
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color(.systemGray6)).cornerRadius(8)

                    if vm.isLoading {
                        VStack(spacing: 12) { ProgressView(); Text("正在逐张生成提示词...").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if !vm.prompts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("提示词列表").font(.subheadline.bold())
                            ForEach(vm.prompts) { pr in
                                PromptCardRow(card: pr, isGenerating: vm.currentGeneratingIndex == pr.cardIndex, onCopy: { vm.copyPrompt(at: vm.prompts.firstIndex(where: { $0.id == pr.id }) ?? 0) }, onRegenerate: { vm.regenerateSingle(at: pr.cardIndex) }, onEdit: { editingCardIndex = pr.cardIndex; editText = pr.promptText })
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
                    Button("下一步：出图") { goNext = true }.buttonStyle(.borderedProminent).disabled(vm.nonEmptyPromptCount == 0)
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
        .sheet(item: $editingCardIndex) { idx in
            if idx < vm.prompts.count {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text("编辑图\(idx+1) 提示词").font(.headline)
                        TextEditor(text: $editText).font(.system(size: 13, design: .monospaced)).frame(minHeight: 200).padding(8).background(Color(.systemGray6)).cornerRadius(8)
                        HStack(spacing: 12) {
                            Button("取消") { editingCardIndex = nil }.buttonStyle(.bordered)
                            Button("保存") { vm.updatePrompt(at: idx, prompt: editText, description: ""); editingCardIndex = nil }.buttonStyle(.borderedProminent)
                        }
                    }.padding()
                }
            }
        }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }
}

struct PromptCardRow: View {
    let card: PromptCard
    let isGenerating: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("图\(card.cardIndex+1)").font(.caption).fontWeight(.semibold).foregroundColor(.white).padding(.horizontal, 8).padding(.vertical, 4).background(statusColor).cornerRadius(6)
                Spacer()
                Text(statusText).font(.caption2).foregroundColor(statusColor)
                if !card.promptText.isEmpty { Button(action: onCopy) { Image(systemName: "doc.on.doc").font(.caption) }.buttonStyle(.plain) }
                Button(action: onEdit) { Image(systemName: "pencil").font(.caption) }.buttonStyle(.plain).tint(.blue)
                if card.status == .success || card.status == .failed { Button(action: onRegenerate) { Image(systemName: "arrow.clockwise").font(.caption) }.buttonStyle(.plain) }
            }
            if isGenerating {
                HStack { ProgressView().scaleEffect(0.8); Text("生成中...").font(.caption).foregroundColor(.secondary) }.padding(.vertical, 8)
            } else if card.status == .success && !card.promptText.isEmpty {
                Text(card.promptText).font(.system(size: 12, design: .monospaced)).foregroundColor(.primary).lineLimit(10)
            } else if card.status == .failed {
                VStack(alignment: .leading, spacing: 4) { Text("（生成失败）").font(.caption).foregroundColor(.red); if let err = card.errorMessage { Text(err).font(.caption2).foregroundColor(.secondary) } }
            } else if card.status == .pending { Text("（等待生成）").font(.caption).foregroundColor(.secondary) }
        }
        .padding().background(card.status == .success ? Color.green.opacity(0.04) : Color(.systemGray6)).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isGenerating ? Color.orange.opacity(0.5) : Color.clear, lineWidth: isGenerating ? 1.5 : 0.5))
    }
    private var statusText: String {
        switch card.status { case .pending:"等待生成"; case .generating:"生成中..."; case .success:"✅ 已生成"; case .failed:"❌ 失败" }
    }
    private var statusColor: Color {
        switch card.status { case .pending:.secondary; case .generating:.orange; case .success:.green; case .failed:.red }
    }
}
