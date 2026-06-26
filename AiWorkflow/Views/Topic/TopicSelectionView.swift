import SwiftUI

struct TopicSelectionView: View {
    @Environment(\.projectStore) private var store
    @Environment(\.textService) private var textService
    @StateObject private var vm = TopicViewModel()
    @State private var goNext = false
    let projectID: UUID

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ProgressHeader(title: vm.project?.name ?? "选题", step: 1, total: 4, tint: .blue)

                VStack(alignment: .leading, spacing: 8) {
                    Label("账号定位", systemImage: "target").font(.subheadline.bold())
                    TextEditor(text: $vm.positioningInput).frame(minHeight: 80).padding(8)
                        .background(Color(.systemGray6)).cornerRadius(8)
                    Button { vm.generateTopics() } label: { HStack { Image(systemName: "sparkles"); Text(vm.isLoading ? "生成中..." : "生成选题") }.frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).disabled(vm.isLoading)
                }

                if vm.isLoading {
                    VStack(spacing: 12) { ProgressView().scaleEffect(1.5); Text("AI正在生成选题...").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if vm.topics.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "lightbulb").font(.system(size: 40)).foregroundColor(.secondary); Text("输入定位，点击生成").foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("选题列表", systemImage: "list.bullet").font(.subheadline.bold())
                        ForEach(vm.topics) { t in
                            Button { vm.selectTopic(t) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(t.title).font(.subheadline).fontWeight(t.id == vm.selectedTopicID ? .semibold : .regular).lineLimit(2)
                                        if !t.topicDescription.isEmpty { Text(t.topicDescription).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                                    }
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Button { vm.toggleFavorite(t) } label: { Image(systemName: t.isFavorited ? "heart.fill" : "heart").foregroundColor(t.isFavorited ? .red : .gray).font(.caption) }.buttonStyle(.plain)
                                        if t.id == vm.selectedTopicID { Image(systemName: "checkmark.circle.fill").foregroundColor(.blue) }
                                    }
                                }.padding().background(RoundedRectangle(cornerRadius: 10).stroke(t.id == vm.selectedTopicID ? Color.blue : Color(.systemGray5), lineWidth: t.id == vm.selectedTopicID ? 2 : 1))
                            }.buttonStyle(.plain)
                        }
                        if vm.selectedTopicID != nil {
                            Button { goNext = true } label: { Text("选择此选题，进入文案编辑").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        }
                        Button("重新生成") { vm.generateTopics() }.disabled(vm.isLoading).frame(maxWidth: .infinity)
                    }
                }
            }.padding()
        }
        .navigationTitle("选题").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goNext) {
            if let pid = vm.selectedTopicID, let p = vm.project { CopyEditingView(projectID: projectID) }
        }
        .onAppear { if let p = store.project(id: projectID) { vm.setup(store: store, textService: textService, project: p) } }
    }
}
