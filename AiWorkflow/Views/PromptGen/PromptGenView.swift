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
                    promptToolbar
                    promptCards
                }.padding()
            }
            promptBottomBar
        }
        .navigationTitle("提示词").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) { ImageGenView(projectID: projectID) }
        .sheet(isPresented: $showBatchImport) { VStack { Text("批量导入提示词").font(.headline); TextEditor(text: $batchText).frame(minHeight: 150).padding(8); Button("导入") { vm.batchImportPrompts(batchText); showBatchImport = false; batchText = "" }.buttonStyle(.borderedProminent) }.padding() }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }

    private var promptToolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { vm.generatePrompts() } label: {
                    HStack { Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "根据文案生成").font(.subheadline) }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                if vm.nonEmptyPromptCount > 0 { Button("复制全部") { vm.copyAllPrompts() }.buttonStyle(.bordered).controlSize(.small) }
            }
            HStack(spacing: 12) {
                Button("批量导入") { showBatchImport = true }.buttonStyle(.bordered).tint(.blue)
                Text("\(vm.nonEmptyPromptCount)/\(vm.prompts.count) 条").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var promptCards: some View {
        Group {
            if vm.prompts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("点击「根据文案生成」或「批量导入」").foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.prompts) { pr in
                        PromptSimpleRow(text: pr.promptText, index: pr.cardIndex, isGenerating: vm.currentGeneratingIndex == pr.cardIndex, onEdit: { self.vm.updatePrompt(at: pr.cardIndex, prompt: $0, description: "") }, onCopy: { self.vm.copyPrompt(at: pr.cardIndex) })
                    }
                }
            }
        }
    }

    private var promptBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("下一歩：出图") { goNext = true }.buttonStyle(.borderedProminent).disabled(vm.nonEmptyPromptCount == 0)
                Spacer()
                if let m = vm.lastCopied { Text("已复制").font(.caption).foregroundColor(.green) }
            }.padding()
        }.background(Color(.systemBackground))
    }

