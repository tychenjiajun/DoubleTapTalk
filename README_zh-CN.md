# DoubleTapTalk 中文文档

<div align="center">

**macOS 语音转文字助手**

双击快捷键激活，快速转录并输入到任何应用程序

[English Version](README.md)

</div>

---

## 概述

DoubleTapTalk 是一款轻量级 macOS 菜单栏应用，通过双击快捷键实现语音转文字功能。双击 Control 键开始录音，自然说话，然后单击停止（不带优化）或双击停止（带 AI 优化），文字会自动出现在当前应用的光标位置。

### ✨ 功能特点

#### 核心功能
- **🎤 按键录音**: 双击 Control 键开始录音
- **⏱️ 智能热键控制**:
  - 双击 Control → 开始录音
  - 单击 Control → 停止，不进行优化
  - 双击 Control → 停止，进行 AI 优化
- **🌐 多语言支持**: 自动检测或从 100+ 种语言中手动选择
- **🔒 安全存储**: API 密钥加密存储在 macOS Keychain
- **🚫 无 Dock 图标**: 安静地运行在菜单栏中

#### 多种语音识别后端
选择您偏好的语音识别服务：
- **OpenAI Whisper**（云端）- 高精度，需要 API 密钥
- **Groq**（云端）- 边缘硬件上的快速推理
- **DashScope ASR Flash**（云端）- DashScope 高级模型，中文效果极佳
- **本地 whisper.cpp**（离线）- 免费、隐私友好，需自托管服务器

#### AI 文本优化（可选）
使用大模型改进转录文本：
- **多提供商支持**: OpenAI、Anthropic、Google、ModelScope
- **自定义 Base URL**: 连接 Ollama、LM Studio、vLLM 等
- **可配置超时**: 1-30 秒（默认 5 秒）
- **优雅降级**: 超时或错误时自动回退到原文
- **系统提示词定制**: 调整优化行为

#### 开发者友好
- **全面日志**: 调试位置 `~/Library/Caches/DoubleTapTalk.log`
- **辅助脚本**: `view-logs.sh`、`check-polish-logs.sh`、`test-injection.sh`
- **Swift Package Manager**: 干净的构建系统
- **模块化架构**: 易于扩展后端/服务

### 📋 系统要求

- **macOS 13.0+** (Ventura 或更高版本)
- **权限**:
  - 麦克风访问（用于录音）
  - 辅助功能权限（用于热键和文本注入）
- **API 密钥**（选择其一）:
  - OpenAI API 密钥，或
  - Groq API 密钥，或
  - 阿里云 DashScope/ModelScope API 密钥，或
  - 正在运行的本地 whisper.cpp 服务器

### 🚀 快速开始

#### 安装

**方式一：下载 DMG**
```bash
# 下载最新版本的 DMG
open DoubleTapTalk-1.0.0.dmg
# 将 DoubleTapTalk.app 拖入应用程序文件夹
```

**方式二：从源代码构建**
```bash
git clone https://github.com/tychenjiajun/voice-key.git
cd voice-key
swift build -c release
open DoubleTapTalk.app
```

#### 首次设置

1. **授予权限**:
   - 前往 系统设置 → 隐私与安全性 → 辅助功能
   - 将 "DoubleTapTalk" 添加到列表
   - 提示时也授予麦克风权限

2. **配置后端**（⌘, 打开设置）:
   - 选择首选的 ASR 后端
   - 输入 API 密钥（安全保存到 Keychain）
   - 选择语言（推荐自动检测）

3. **开始使用**:
   - 注意菜单栏中的麦克风图标
   - 双击 Control → 说话 → 释放
   - 文字出现在当前应用光标位置！

### ⚙️ 配置说明

#### ASR 设置
- **后端类型**: OpenAI / Groq / DashScope / 本地
- **API 密钥**: 存储在 Keychain（com.jiajun.doubletaptalk.app）
- **语言**: 自动 / zh-CN / en / 还有 100+ 种
- **模型**: whisper-1 / whisper-large-v3 / qwen3-asr-flash

#### AI 优化设置（可选）
- **启用优化**: 开关选项
- **提供商**: OpenAI / Anthropic / Google / 自定义
- **模型**: gpt-4o-mini / claude-3-haiku / gemini-pro 等
- **温度值**: 0.0 - 1.0（创造性）
- **自定义 Base URL**: 用于 Ollama/LM Studio/vLLM（例如 http://localhost:11434/v1）
- **超时时间**: 1-30 秒（防止卡住）
- **系统提示词**: 自定义优化行为

#### 热键配置
- **录音触发**: 双击 Control
- **停止行为**: 单击 = 不优化，双击 = 带优化
- **菜单按钮**: 总是停止且不带优化

### 🔧 开发指南

#### 构建项目
```bash
# 调试构建
swift build

# 发布构建（推荐）
swift build -c release

# 直接运行
.build/debug/DoubleTapTalk
```

#### 运行测试
```bash
# 实时查看日志
./view-logs.sh watch

# 检查优化状态
./check-polish-logs.sh

# 测试文本注入
./test-injection.sh browser  # 或 'native'
```

#### 日志文件位置
所有操作记录到：`~/Library/Caches/DoubleTapTalk.log`

日志级别：
- **DEBUG**: 详细 API 调用、JSON 响应、token 使用量
- **INFO**: 状态变化、成功操作
- **WARN**: 非关键问题
- **ERROR**: 失败信息及降级详情

### 🛠️ 故障排除

#### 热键不工作
```
1. 退出 DoubleTapTalk
2. 系统设置 → 隐私与安全性 → 辅助功能
3. 找到 "DoubleTapTalk"，删除后重新添加
4. 重启 DoubleTapTalk
```

#### 转录返回空结果
检查日志文件的错误详情：
```bash
tail -30 ~/Library/Caches/DoubleTapTalk.log | grep -i error
```

常见原因：
- API 密钥无效
- 网络连接问题
- 所选后端不支持该模型

#### 优化功能优雅降级
如果 AI 优化超时或失败，会自动使用原始转录文本。

如持续失败，可在设置中增加超时时间。

### 📝 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

### 🤝 贡献

欢迎贡献！请随时提交问题或拉取请求。

### 📄 文档

- [英文版](README.md)
- [中文版](README_zh-CN.md) （本文档）

---

<div align="center">

用心打造 by Jiajun Chen | 开源许可：MIT

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macos-13%2B-green.svg)](https://www.apple.com/mac/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)

</div>
