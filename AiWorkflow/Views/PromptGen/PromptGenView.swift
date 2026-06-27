import SwiftUI

struct PromptGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = PromptViewModel()
    @State private var goNext = false
    @State private var showBatchImport = false
    @State private var batchText: String = ""
    @State private var showBatchImport = false
    @State private var batchText: String = ""
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 3, total: 4, tint: .orange) }

                    // 工具按钮
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button { vm.generatePrompts() } label: {
                                HStack { Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "根据文案生成").font(.subheadline) }.frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                            if vm.nonEmptyPromptCount > 0 { Button("复制全部") { vm.copyAllPrompts() }.buttonStyle(.bordered).controlSize(.small) }
                            Button("批量导入") { showBatchImport = true }.buttonStyle(.bordered).controlSize(.small)
                        }
                        HStack(spacing: 12) {
                            Button { showBatchImport = true } label: {
                                HStack { Image(systemName: "doc.badge.plus"); Text("批量导入提示词").font(.caption) }.frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered).tint(.blue)
                            Text("\(vm.nonEmptyPromptCount)/\(vm.prompts.count) 条").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    // 卡片列表
                    if !vm.prompts.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(vm.prompts) { pr in
                                PromptCardEditRow(
                                    card: Binding(
                                        get: { pr },
                                        set: { updated in
                                            if let idx = vm.prompts.firstIndex(where: { $0.id == pr.id }) {
                                                vm.updatePrompt(at: idx, prompt: updated.promptText, description: "")
                                            }
                                        }
                                    ),
                                    isGenerating: vm.currentGeneratingIndex == pr.cardIndex,
                                    onCopy: { vm.copyPrompt(at: vm.prompts.firstIndex(where: { $0.id == pr.id }) ?? 0) },
                                    onRegenerate: { vm.regenerateSingle(at: pr.cardIndex) }
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundColor(.secondary)
                            Text("点击「根据文案生成」或「批量导入」").foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }.padding()
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("下一歩：出图") { goNext = true }.buttonStyle(.borderedProminent).disabled(vm.nonEmptyPromptCount == 0)
                    Spacer()
                    if let m = vm.lastCopied { Text("已复制").font(.caption).foregroundColor(.green) }
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("提示词").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) { ImageGenView(projectID: projectID) }
        .sheet(isPresented: $showBatchImport) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("批量导入提示词").font(.headline)
                    Text("每行一条，或空行分隔。支持\"第N条\"格式。").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $batchText).font(.system(size: 13, design: .monospaced)).frame(minHeight: 200).padding(8).background(Color(.systemGray6)).cornerRadius(8)
                    HStack(spacing: 12) {
                        Button("取消") { showBatchImport = false; batchText = "" }.buttonStyle(.bordered)
                        Button("导入并填充") {
                            vm.batchImportPrompts(batchText)
                            showBatchImport = false; batchText = ""
                        }.buttonStyle(.borderedProminent).disabled(batchText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }
}

// MARK: - 可编辑提示词行

struct PromptCardEditRow: View {
    @Binding var card: PromptCard
    let isGenerating: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var editText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("图\(card.cardIndex+1)").font(.caption).fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(statusColor).cornerRadius(6)
                Spacer()
                if !card.promptText.isEmpty { Button(action: onCopy) { Image(systemName: "doc.on.doc").font(.caption) }.buttonStyle(.plain) }
            }

            if isGenerating {
                HStack { ProgressView().scaleEffect(0.8); Text("生成中...").font(.caption).foregroundColor(.secondary) }.padding(.vertical, 8)
            } else {
                TextEditor(text: $editText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                    .onChange(of: editText) { newVal in
                        card.promptText = newVal
                        if !newVal.isEmpty { card.status = .success }
                    }
            }
        }
        .padding(12).background(cardBackground).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: isGenerating ? 1.5 : 0.5))
        .onAppear { editText = card.promptText }
        .onChange(of: card.promptText) { newVal in
            if newVal != editText { editText = newVal }
        }
    }

    private var statusColor: Color {
        if !card.promptText.isEmpty { return .green }
        return .secondary
    }
    private var cardBackground: Color {
        !card.promptText.isEmpty ? Color.green.opacity(0.04) : Color(.systemGray6)
    }
    private var borderColor: Color {
        isGenerating ? Color.orange.opacity(0.5) : Color.clear
    }
}
