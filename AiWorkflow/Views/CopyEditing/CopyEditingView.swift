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
                    ProgressHeader(title: vm.project?.name ?? "文案", step: 2, total: 4, tint: .purple)
                    HStack { Image(systemName: "quote.opening").foregroundColor(.blue); Text(userTopic).font(.subheadline); Spacer() }
                        .padding().background(Color.blue.opacity(0.08)).cornerRadius(10)

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

                    if !vm.parseMode.isEmpty {
                        Text("解析模式: \(vm.parseMode)  |  卡片: \(vm.cards.count) 张")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    // ── 卡片内容 ──
                    if vm.isLoading {
                        VStack(spacing: 12) { ProgressView(); Text(vm.progressText).foregroundColor(.secondary) }
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if !vm.cards.isEmpty {
                        Text(vm.progressText).font(.caption).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("文案列表（\(vm.cards.count)张）").font(.subheadline.bold())
                            ForEach(vm.cards) { card in
                                CopyCardRow(
                                    card: card,
                                    onUpdate: { top, bottom, purpose in
                                        if let idx = vm.cards.firstIndex(where: { $0.id == card.id }) {
                                            vm.updateCard(index: idx, topText: top, bottomText: bottom, purpose: purpose)
                                        }
                                    }
                                )
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text").font(.system(size: 40)).foregroundColor(.secondary)
                            Text("点击「生成文案」或「加载测试文案」开始").foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }

                    // ── 原始响应调试区 ──
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

            VStack(spacing: 0) {
                Divider()
                HStack {
                    let nonEmpty = vm.cards.filter { !$0.topText.isEmpty || !$0.bottomText.isEmpty }.count
                    Text("\(nonEmpty)/\(vm.cards.count) 张已填写").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("下一步：生图提示词") { goNext = true }
                        .font(.subheadline).buttonStyle(.borderedProminent)
                        .disabled(nonEmpty == 0)
                }.padding()
            }.background(Color(.systemBackground))
        }
        .navigationTitle("文案编辑").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) {
            if let p = vm.project { PromptGenView(projectID: p.id) }
        }
        .onAppear {
            print("🔵 [UI] CopyEditingView projectID=\(projectID)")
            if let p = store.project(id: projectID) {
                vm.setup(store: store, textService: textService, project: p, userTopic: userTopic, extraRequirements: extraRequirements)
            } else { alertMsg = "项目不存在"; showAlert = true }
        }
        .onChange(of: vm.errorMessage) { msg in if let m = msg, !m.isEmpty { alertMsg = m; showAlert = true } }
        .alert("提示", isPresented: $showAlert) { Button("确定") { vm.errorMessage = nil } } message: { Text(alertMsg) }
    }
}

// MARK: - 单张卡片子视图

struct CopyCardRow: View {
    let card: CopywritingCard
    let onUpdate: (String, String, String) -> Void

    @State private var topText: String = ""
    @State private var bottomText: String = ""
    @State private var purpose: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("第\(card.cardIndex + 1)张").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            // 调试显示
            HStack {
                if !topText.isEmpty { Text("上: \(topText.prefix(20))...").font(.caption2).foregroundColor(.green) }
                if !bottomText.isEmpty { Text("下: \(bottomText.prefix(20))...").font(.caption2).foregroundColor(.green) }
                if !purpose.isEmpty { Text("作用: \(purpose)").font(.caption2).foregroundColor(.secondary) }
            }

            VStack(spacing: 0) {
                TextField("上半格文案", text: $topText, axis: .vertical)
                    .textFieldStyle(.plain).padding().lineLimit(2...3)
                Divider().padding(.leading)
                TextField("下半格文案", text: $bottomText, axis: .vertical)
                    .textFieldStyle(.plain).padding().lineLimit(2...3)
            }
            .background(Color(.systemGray6)).cornerRadius(10)
            .onChange(of: topText) { _ in onUpdate(topText, bottomText, purpose) }
            .onChange(of: bottomText) { _ in onUpdate(topText, bottomText, purpose) }
            .onChange(of: purpose) { _ in onUpdate(topText, bottomText, purpose) }
        }
        .onAppear {
            topText = card.topText
            bottomText = card.bottomText
            purpose = card.purpose
            print("📱 [CopyCardRow] card[\(card.cardIndex)] appear: top=「\(card.topText)」 bottom=「\(card.bottomText)」")
        }
        .onChange(of: card.id) { _ in
            topText = card.topText
            bottomText = card.bottomText
            purpose = card.purpose
            print("📱 [CopyCardRow] card[\(card.cardIndex)] id changed, reload: top=「\(card.topText)」")
        }
    }
}
