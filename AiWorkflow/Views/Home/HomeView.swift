import SwiftUI

struct HomeView: View {
    @Environment(\.projectStore) private var store
    @StateObject private var vm = HomeViewModel()
    @State private var newSheet = false
    @State private var settingsSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.projects.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "square.on.square.dashed").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("还没有项目").font(.title2)
                        Text("新建你的第一个双格漫画项目").foregroundColor(.secondary)
                        Button { newSheet = true } label: { Label("新建项目", systemImage: "plus").font(.headline) }
                            .buttonStyle(.borderedProminent).padding(.top, 8)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            quickActions
                            if !vm.recentProjects.isEmpty { recentSection }
                            allSection
                        }.padding()
                    }.refreshable { vm.reload() }
                }
            }
            .navigationTitle("AI图文工作流")
            .searchable(text: $vm.searchText, prompt: "搜索项目...")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { settingsSheet = true } label: { Image(systemName: "gearshape") } } }
            .sheet(isPresented: $newSheet) { NewProjectView { p in
                guard let p = p else { return }
                vm.createProject(name: p.name) } }
            .sheet(isPresented: $settingsSheet) { SettingsView() }
            .navigationDestination(for: Project.self) { p in TopicSelectionView(projectID: p.id) }
            .onAppear { vm.setup(store: store) }
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            Button { newSheet = true } label: { VStack(spacing: 12) { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.blue); Text("新建项目").font(.subheadline).fontWeight(.medium) }.frame(maxWidth: .infinity).padding(.vertical, 20).background(Color(.systemGray6)).cornerRadius(12) }
            Button { } label: { VStack(spacing: 12) { Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundColor(.purple); Text("历史项目").font(.subheadline).fontWeight(.medium) }.frame(maxWidth: .infinity).padding(.vertical, 20).background(Color(.systemGray6)).cornerRadius(12) }
            Button { settingsSheet = true } label: { VStack(spacing: 12) { Image(systemName: "gearshape.fill").font(.title2).foregroundColor(.gray); Text("设置").font(.subheadline).fontWeight(.medium) }.frame(maxWidth: .infinity).padding(.vertical, 20).background(Color(.systemGray6)).cornerRadius(12) }
            Button { } label: { VStack(spacing: 12) { Image(systemName: "chart.bar.fill").font(.title2).foregroundColor(.orange); Text("统计").font(.subheadline).fontWeight(.medium) }.frame(maxWidth: .infinity).padding(.vertical, 20).background(Color(.systemGray6)).cornerRadius(12) }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近项目", systemImage: "clock").font(.headline)
            ForEach(vm.recentProjects) { p in
                NavigationLink(value: p) { ProjectCardView(project: p) }.buttonStyle(.plain)
                    .contextMenu { Button("删除", role: .destructive) { vm.deleteProject(p) } }
            }
        }
    }

    private var allSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部项目").font(.headline)
            ForEach(vm.filteredProjects) { p in
                NavigationLink(value: p) { ProjectCardView(project: p) }.buttonStyle(.plain)
                    .contextMenu { Button("删除", role: .destructive) { vm.deleteProject(p) } }
            }
        }
    }
}

extension Project: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
