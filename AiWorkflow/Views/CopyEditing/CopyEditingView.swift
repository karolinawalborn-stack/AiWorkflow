import SwiftUI

struct CopyEditingView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = CopyEditViewModel()
    @State private var goNext = false
    let projectID: UUID

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ProgressHeader(title: vm.project?.name ?? "文案", step: 2, total: 4, tint: .purple)

                if let t = vm.selectedTopic {
                    HStack { Image(systemName: "target").foregroundColor(.blue); Text(t.title).font(.subheadline); Spacer() }.padding().background(Color.blue.opacity(0.08)).cornerRadius(10)
                }

                Button { vm.generateCopy() } label: { HStack { Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "生成文案") }.frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(vm.isLoading)

                if vm.isLoading {
                    VStack(spacing: 12) { ProgressView(); Text(vm.progressText).foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if vm.cards.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "doc.text").font(.system(size: 40)).foregroundColor(.secondary); Text("点击生成文案").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
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
                }
            }.padding()
        }
        .navigationTitle("文案编辑").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("下一步") { goNext = true }.disabled(vm.cards.isEmpty) } }
        .navigationDestination(isPresented: $goNext) { PromptGenView(projectID: projectID) }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }
}
