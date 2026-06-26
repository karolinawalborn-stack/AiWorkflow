import SwiftUI

struct CopyEditingView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = CopyEditViewModel()
    @State private var goNext = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    let projectID: UUID
    let userTopic: String
    let extraRequirements: String

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ProgressHeader(title: vm.project?.name ?? "文案", step: 2, total: 4, tint: .purple)

                // 显示用户输入的选题
                HStack { Image(systemName: "quote.opening").foregroundColor(.blue); Text(userTopic).font(.subheadline); Spacer() }.padding().background(Color.blue.opacity(0.08)).cornerRadius(10)

                // 操作按钮
                VStack(spacing: 8) {
                    Button { print("🔵 [UI] 生成文案按钮点击"); vm.generateCopy() } label: {
                        HStack { if vm.isLoading { ProgressView().tint(.white) }; Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "生成文案") }.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(vm.isLoading)

                    Button { vm.loadMockCopy() } label: {
                        HStack { Image(systemName: "ladybug"); Text("加载测试文案（跳过 API）") }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(.orange)
                }

                // 进度/结果/空态
                if vm.isLoading {
                    VStack(spacing: 12) { ProgressView(); Text(vm.progressText).foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if !vm.cards.isEmpty && !vm.cards.allSatisfy({ $0.isEmpty }) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("文案（\(vm.cards.count)张）").font(.subheadline.bold())
                        ForEach(Array(vm.cards.enumerated()), id: \.element.id) { idx, card in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第\(card.cardIndex+1)张").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                                VStack(spacing: 0) {
                                    TextField("上半格：受压/委屈", text: Binding(get: { card.topFrame }, set: { vm.updateCard(index: idx, top: $0, bottom: card.bottomFrame) }), axis: .vertical).textFieldStyle(.plain).padding().lineLimit(2...3)
                                    Divider().padding(.leading)
                                    TextField("下半格：清醒/反击", text: Binding(get: { card.bottomFrame }, set: { vm.updateCard(index: idx, top: card.topFrame, bottom: $0) }), axis: .vertical).textFieldStyle(.plain).padding().lineLimit(2...3)
                                }.background(Color(.systemGray6)).cornerRadius(10)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) { Image(systemName: "doc.text").font(.system(size: 40)).foregroundColor(.secondary); Text("点击「生成文案」开始").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }.padding()
        }
        .navigationTitle("文案编辑").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("下一步") { goNext = true }.disabled(vm.cards.isEmpty || vm.cards.allSatisfy({ $0.isEmpty })) } }
        .navigationDestination(isPresented: $goNext) { PromptGenView(projectID: projectID) }
        .onAppear {
            print("🔵 [UI] CopyEditingView.onAppear, projectID=\(projectID)")
            if let p = store.project(id: projectID) {
                print("✅ [UI] 找到 project: \(p.name)")
                vm.setup(store: store, textService: textService, project: p, userTopic: userTopic, extraRequirements: extraRequirements)
            } else {
                print("❌ [UI] project 未找到: \(projectID)")
                alertMsg = "项目数据未找到"; showAlert = true
            }
        }
        .onChange(of: vm.errorMessage) { msg in if let m = msg { alertMsg = m; showAlert = true } }
        .alert("提示", isPresented: $showAlert) { Button("确定") { vm.errorMessage = nil } } message: { Text(alertMsg) }
    }
}
