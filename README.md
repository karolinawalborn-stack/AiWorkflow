# AiWorkflow — 抖音爆款双格漫画工作流工具

## 赛道
双格漫画（婚姻情感 / 职场压榨 / 亲情委屈 / 人性清醒 / 讨好型人格）
- 3:4 竖版，上下双格布局，带字幕框
- 深蓝黑压抑情绪漫画风格
- 白色圆头小人 IP
- 文案逻辑：上半格受压 → 下半格清醒

## 工作流
```
选题 → 出文案 → 生图提示词 → GPT Image 2 出图 → 保存
├─ GPT-5.4    ├─ GPT-5.4    ├─ GPT-5.4    ├─ GPT Image 2
│  6 个选题    │  6 张图      │  6 条 Prompt  │  逐张出图
│  选1个      │  上/下双格    │  可编辑/复制  │  可导出相册
```

## AI 模型配置（已预填）
| 参数 | 值 |
|------|------|
| API Base URL | `https://api.lk888.ai/api` |
| API Key | `sk-1c22e331ff128e7f4d62eff86a5e2caccdbb67e07db70011` |
| 文本模型 | `gpt-5.4` |
| 图片模型 | `gpt-image-2` |

## 编译说明

### Windows 用户（推荐）
1. 推送到 GitHub
2. Actions 自动在云端 Mac 编译
3. 下载 IPA → TrollStore 安装

```bash
git init
git add .
git commit -m "init"
git remote add origin https://github.com/你的用户名/AiWorkflow.git
git push -u origin main
# → 去 GitHub Actions 页面下载 IPA
```

### Mac 用户
```bash
brew install xcodegen
xcodegen generate
open AiWorkflow.xcodeproj
# Xcode → Product → Build → 导出 .app → 打包 IPA
```

## 架构
```
Models/Project.swift       ← 自包含聚合根（全部子模型内嵌）
Data/ProjectStore.swift    ← JSON 文件持久化
Services/                  ← 协议 + Mock + 真实实现 + 配置适配
ViewModels/                ← 8 个 @MainActor ObservableObject
Views/                     ← 8 个页面（无 iOS 17+ API）
```

## 兼容性
- iOS 16.0+
- TrollStore（无 Apple ID / 证书）
- 零第三方依赖
