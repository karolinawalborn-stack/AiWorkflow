import SwiftUI

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = NewProjectViewModel()
    let onSave: ((Project?) -> Void)?
    private let editing: Project?
    private let isEditing: Bool

    init(project: Project? = nil, onSave: ((Project?) -> Void)? = nil) {
        self.onSave = onSave; self.editing = project; self.isEditing = project != nil
        if let p = project { let v = NewProjectViewModel(); v.load(from: p); _vm = StateObject(wrappedValue: v) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("项目名称", text: $vm.projectName).submitLabel(.done)
                    Picker("赛道", selection: $vm.category) { ForEach(vm.categoryOptions, id: \.self) { Text($0).tag($0) } }
                    TextField("内容风格", text: $vm.style, axis: .vertical).lineLimit(2...4)
                } header: { Text("基本信息").foregroundColor(.secondary) }

                Section {
                    HStack { Text("图数"); Spacer(); Picker("", selection: $vm.imageCount) { ForEach(vm.imageCountOptions, id: \.self) { Text("\($0)张").tag($0) } }.pickerStyle(.segmented) }
                    Picker("比例", selection: $vm.ratio) { ForEach(vm.ratioOptions, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    TextField("IP风格描述", text: $vm.ipStyle, axis: .vertical).lineLimit(3...6)
                } header: { Text("内容配置").foregroundColor(.secondary) }
            }
            .navigationTitle(isEditing ? "编辑" : "新建项目").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { guard vm.isFormValid else { return }; let p = vm.buildProject(existing: editing); dismiss(); onSave?(p) }.disabled(!vm.isFormValid)
                }
            }
        }
    }
}
