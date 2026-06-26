import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                // API 配置
                Section {
                    VStack(alignment: .leading, spacing: 4) { Text("API Base URL").font(.caption).foregroundColor(.secondary); TextField("https://api.lk888.ai/api", text: $vm.apiBaseURL).textContentType(.URL).autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL) }
                    VStack(alignment: .leading, spacing: 4) { Text("API Key").font(.caption).foregroundColor(.secondary)
                        HStack { if vm.isAPIKeyVisible { TextField("sk-...", text: $vm.apiKey).autocapitalization(.none).disableAutocorrection(true) } else { SecureField("sk-...", text: $vm.apiKey) }
                            Button { vm.isAPIKeyVisible.toggle() } label: { Image(systemName: vm.isAPIKeyVisible ? "eye.slash" : "eye").foregroundColor(.secondary) }.buttonStyle(.plain) }
                    }
                    Button { Task { await vm.validateConnection() } } label: { HStack { Image(systemName: "antenna.radiowaves.left.and.right"); Text(vm.isValidating ? "验证中..." : "验证连接") } }.disabled(vm.isValidating)
                } header: { Text("API配置").foregroundColor(.secondary) }

                // 模型配置
                Section {
                    VStack(alignment: .leading, spacing: 4) { Text("文本模型 (GPT-5.4)").font(.caption).foregroundColor(.secondary); TextField("gpt-5.4", text: $vm.textModelID).autocapitalization(.none).disableAutocorrection(true) }
                    VStack(alignment: .leading, spacing: 4) { Text("图片模型 (GPT Image 2)").font(.caption).foregroundColor(.secondary); TextField("gpt-image-2", text: $vm.imageModelID).autocapitalization(.none).disableAutocorrection(true) }
                } header: { Text("模型配置").foregroundColor(.secondary) }

                // 选题模板
                Section {
                    TextEditor(text: $vm.topicTemplate).frame(minHeight: 120).font(.caption)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                    Button("恢复默认选题模板") { vm.topicTemplate = PromptTemplates.default.topic; vm.saveTemplates() }
                } header: { Text("选题模板（System Prompt）").foregroundColor(.secondary) }

                // 文案模板
                Section {
                    TextEditor(text: $vm.copyTemplate).frame(minHeight: 120).font(.caption)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                    Button("恢复默认文案模板") { vm.copyTemplate = PromptTemplates.default.copywriting; vm.saveTemplates() }
                } header: { Text("文案模板（System Prompt）").foregroundColor(.secondary) }

                // 生图提示词模板
                Section {
                    TextEditor(text: $vm.promptTemplate).frame(minHeight: 120).font(.caption)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                    Button("恢复默认提示词模板") { vm.promptTemplate = PromptTemplates.default.imagePrompt; vm.saveTemplates() }
                } header: { Text("生图提示词模板（System Prompt）").foregroundColor(.secondary) }

                // 关于
                Section {
                    HStack { Text("版本"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                    HStack { Text("目标平台"); Spacer(); Text("iOS 16+ / TrollStore").foregroundColor(.secondary) }
                    HStack { Text("赛道"); Spacer(); Text("双格漫画").foregroundColor(.secondary) }
                } header: { Text("关于").foregroundColor(.secondary) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                // 离开设置页时自动保存 API 配置和模板
                vm.save()
                vm.saveTemplates()
            }
        }
    }
}
