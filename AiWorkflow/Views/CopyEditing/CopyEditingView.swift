import SwiftUI

struct CopyEditingView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = CopyEditViewModel()
    @State private var goNext = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    @State private var showRaw = false

    let projectID: UUID
    let userTopic: String
    let extraRequirements: String

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // 进度
                    ProgressHeader(title: vm.project?.name ?? "文案", step: 2, total: 4, tint: .purple)
                    HStack { Image(systemName: "quote.opening").foregroundColor(.blue); Text(userTopic).font(.subheadline); Spacer() }
                        .padding().background(Color.blue.opacity(0.08)).cornerRadius(10)

                    // 操作按钮
                    VStack(spacing: 8) {
                        Button { print("🔵 [UI] 生成文案"); vm.generateCopy() } label: {
                            HStack {
                                if vm.isLoading { ProgressView().tint(.white) }
                                Image(systemName: "sparkles")
                                Text(vm.isLoading ? "生成中..." : "生成文案")
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(vm.isLoading)

                        Button { vm.loadMockCopy() } label: {
                            HStack { Image(systemName: "ladybug"); Text("加载测试文案（跳过 API）") }.frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(.orange)
                    }

                    // 解析模式
                    if !vm.parseMode.isEmpty {
                        Text("解析模式: \(vm.parseMode)").font(.caption).foregroundColor(.secondary)
                    }

                    // 内容
                    if vm.isLoading {
                        VStack(spacing: 12) { ProgressView(); Text(vm.progressText).foregroundColor(.secondary) }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if !vm.cards.isEmpty {
                        Text(vm.progressText).font(.caption).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("文案（\(vm.cards.count)张）").font(.subheadline.bold())
                            ForEach(Array(vm.cards.enumerated()), id: \.element.id) { idx, card in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("第\(card.cardIndex + 1)张").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                                    if !card.purpose.isEmpty {
                                        Text("作用：\(card.purpose)").font(.caption2).foregroundColor(.secondary)
                                    }
                                    VStack(spacing: 0) {
                                        TextField("上半格", text: Binding(
                                            get: { card.topText },
                                            set: { vm.updateCard(index: idx, topText: $0, bottomText: card.bottomText, purpose: card.purpose) }
                                        ), axis: .vertical).textFieldStyle(.plain).padding().lineLimit(2...3)
                                        Divider().padding(.leading)
                                        TextField("下半格", text: Binding(
                                            get: { card.bottomText },
                                            set: { vm.updateCard(index: idx, topText: card.topText, bottomText: $0, purpose: card.purpose) }
                                        ), axis: .vertical).textFieldStyle(.plain).padding().lineLimit(2...3)
                                    }.background(Color(.systemGray6)).cornerRadius(10)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text").font(.system(size: 40)).foregroundColor(.secondary)
                            Text("点击「生成文案」或「加载测试文案」开始").foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }

                    // 原始响应调试区
                    if !vm.rawResponse.isEmpty {
                        Button { withAnimation { showRaw.toggle() } } label: {
                            HStack { Image(systemName: showRaw ? "chevron.down" : "chevron.right"); Text("原始响应 (\(vm.rawResponse.count)字符)").font(.caption) }
                        }
                        if showRaw {
                            Text(vm.rawResponse).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(Color(.systemGray6)).cornerRadius(8)
                        }
                    }
                }.padding()
            }

            // 底部工具栏
            VStack(spacing: 0) {
                Divider()
                HStack {
                    if !vm.cards.isEmpty {
                        Text("\(vm.cards.filter { !$0.isEmpty }.count)/\(vm.cards.count) 张已填写")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("下一步：生图提示词") { goNext = true }
                        .font(.subheadline).buttonStyle(.borderedProminent)
                        .disabled(vm.cards.isEmpty || vm.cards.allSatisfy { $0.isEmpty })
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("文案编辑").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) {
            if let p = vm.project { PromptGenView(projectID: p.id) }
        }
        .onAppear {
            print("🔵 [UI] CopyEditingView.onAppear projectID=\(projectID)")
            if let p = store.project(id: projectID) {
                vm.setup(store: store, textService: textService, project: p, userTopic: userTopic, extraRequirements: extraRequirements)
            } else {
                alertMsg = "项目数据未找到"; showAlert = true
            }
        }
        .onChange(of: vm.errorMessage) { msg in
            if let m = msg, !m.isEmpty { alertMsg = m; showAlert = true }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定") { vm.errorMessage = nil }
        } message: { Text(alertMsg) }
    }
}
