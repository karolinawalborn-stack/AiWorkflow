import SwiftUI

struct PromptGenView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = PromptViewModel()
    @State private var goNext = false
    let projectID: UUID

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let p = vm.project { ProgressHeader(title: p.name, step: 3, total: 4, tint: .orange) }

                    HStack(spacing: 12) {
                        Button { vm.generatePrompts() } label: { HStack { Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "生成提示词") }.frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).disabled(vm.isLoading)
                        if !vm.prompts.isEmpty { Button("批量复制") { vm.copyAllPrompts() }.buttonStyle(.bordered) }
                    }

                    if vm.isLoading {
                        VStack(spacing: 12) { ProgressView(); Text("AI生成提示词中...").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if vm.prompts.isEmpty {
                        VStack(spacing: 12) { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundColor(.secondary); Text("点击生成提示词").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("提示词（\(vm.prompts.count)条）").font(.subheadline.bold())
                            ForEach(Array(vm.prompts.enumerated()), id: \.element.id) { idx, pr in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("图\(pr.cardIndex+1)").font(.caption).fontWeight(.semibold).foregroundColor(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange).cornerRadius(6)
                                        Spacer()
                                        Button { vm.copyPrompt(at: idx) } label: { Image(systemName: "doc.on.doc").font(.caption) }.buttonStyle(.plain)
                                    }
                                    if !pr.imageDescription.isEmpty { Text(pr.imageDescription).font(.caption).foregroundColor(.secondary) }
                                    Text(pr.prompt).font(.system(size: 12, design: .monospaced)).lineLimit(5)
                                }.padding().background(Color(.systemGray6)).cornerRadius(10)
                            }
                        }
                    }
                }.padding()
            }
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button("保存为模板") { vm.saveAsTemplate() }.buttonStyle(.bordered)
                    Spacer()
                    Button("下一步：出图") { goNext = true }.buttonStyle(.borderedProminent).disabled(vm.prompts.isEmpty)
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
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }
}
