import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                // ── API 配置 ──
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Base URL").font(.caption).foregroundColor(.secondary)
                        TextField("https://api.lk888.ai/api", text: $vm.apiBaseURL)
                            .textContentType(.URL).autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key").font(.caption).foregroundColor(.secondary)
                        HStack {
                            if vm.isAPIKeyVisible {
                                TextField("sk-...", text: $vm.apiKey).autocapitalization(.none).disableAutocorrection(true)
                            } else {
                                SecureField("sk-...", text: $vm.apiKey)
                            }
                            Button { vm.isAPIKeyVisible.toggle() } label: {
                                Image(systemName: vm.isAPIKeyVisible ? "eye.slash" : "eye").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Button { Task { await vm.validateConnection() } } label: {
                        HStack { Image(systemName: "antenna.radiowaves.left.and.right"); Text(vm.isValidating ? "验证中..." : "验证连接") }
                    }.disabled(vm.isValidating)
                } header: { Text("API 配置").foregroundColor(.secondary) }

                // ── 模型配置 ──
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("文本模型 (GPT-5.4)").font(.caption).foregroundColor(.secondary)
                        TextField("gpt-5.4", text: $vm.textModelID).autocapitalization(.none).disableAutocorrection(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("图片模型 (GPT Image 2)").font(.caption).foregroundColor(.secondary)
                        TextField("gpt-image-2", text: $vm.imageModelID).autocapitalization(.none).disableAutocorrection(true)
                    }
                } header: { Text("模型配置").foregroundColor(.secondary) }

                // ── 三套模板编辑器 ──
                templateSection(template: $vm.topicTemplate, id: "topic", title: "选题模板")
                templateSection(template: $vm.copyTemplate, id: "copywriting", title: "文案模板")
                templateSection(template: $vm.promptTemplate, id: "imagePrompt", title: "生图提示词模板")

                // ── 关于 ──
                Section {
                    HStack { Text("版本"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                    HStack { Text("目标平台"); Spacer(); Text("iOS 16+ / TrollStore").foregroundColor(.secondary) }
                    HStack { Text("赛道"); Spacer(); Text("双格漫画").foregroundColor(.secondary) }
                } header: { Text("关于").foregroundColor(.secondary) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .onDisappear { vm.save() }
        }
    }

    // MARK: - 模板编辑器区块

    @ViewBuilder
    func templateSection(template: Binding<AITemplate>, id: String, title: String) -> some View {
        let isPreview = vm.showPreviewFor == id

        Section {
            // 模板正文编辑
            VStack(alignment: .leading, spacing: 4) {
                Text("模板正文（支持 {{变量名}} 占位符）")
                    .font(.caption).foregroundColor(.secondary)
                TextEditor(text: template.body)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
            }

            // 变量列表
            let variables = template.wrappedValue.variables
            if !variables.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("变量（{{key}} → 实际值）")
                        .font(.caption).foregroundColor(.secondary)
                    ForEach(variables) { v in
                        if let idx = template.wrappedValue.variables.firstIndex(where: { $0.key == v.key }) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("{{\(v.key)}}").font(.caption).foregroundColor(.blue)
                                    Spacer()
                                    Text(v.label).font(.caption2).foregroundColor(.secondary)
                                }
                                TextField(v.label, text: Binding(
                                    get: { template.wrappedValue.variables[idx].value },
                                    set: { template.wrappedValue.variables[idx].value = $0 }
                                ))
                                .font(.system(size: 12))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
            }

            // 操作按钮
            HStack(spacing: 12) {
                Button("恢复默认正文") { vm.resetBody(for: id) }.font(.caption).buttonStyle(.bordered)
                Button("恢复默认变量") { vm.resetVariables(for: id) }.font(.caption).buttonStyle(.bordered)
                Spacer()
                Button(isPreview ? "关闭预览" : "预览") {
                    withAnimation { vm.showPreviewFor = isPreview ? nil : id }
                }.font(.caption).buttonStyle(.borderedProminent)
            }

            // 预览区
            if isPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最终发送给模型的 Prompt 预览")
                        .font(.caption).foregroundColor(.secondary)
                    ScrollView {
                        Text(template.wrappedValue.render())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        } header: { Text(title).foregroundColor(.secondary) }
    }
}
