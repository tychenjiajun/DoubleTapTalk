import SwiftUI
import Carbon

struct SettingsView: View {
    @StateObject private var settings = DoubleTapTalkSettings.shared

    // LLM Polishing state
    @State private var llmApiKeyInput: String = ""
    @State private var showLLMApiKey: Bool = false
    @State private var llmBaseURLInput: String = ""

    // Cloud Transcription state
    @State private var asrApiKeyInput: String = ""
    @State private var showASRApiKey: Bool = false
    @State private var asrBaseURLInput: String = ""

    // Recordings storage state
    @State private var recordingStats: RecordingStoreStats = .empty
    @State private var showDeleteRecordingsConfirm: Bool = false
    @State private var showResetConfirm: Bool = false

    // Permission state
    @State private var hasAccessibilityPermission: Bool = AccessibilityService.shared.hasAccessibilityPermission()
    @State private var micPermission: MicrophonePermission = MicrophonePermissionService.shared.permission()
    @State private var currentMicrophoneName: String? = nil

    /// The settings window follows the same language choice as the overlay and
    /// the menu bar (see `OverlayStyle.language()`), so a Chinese system never
    /// gets a half-translated app.
    private var isChinese: Bool { OverlayStyle.language() == .simplifiedChinese }
    private func copy(_ en: String, _ zh: String) -> String { isChinese ? zh : en }

    var body: some View {
        Form {
            // MARK: - Permissions Section
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.accentColor)
                    Text(copy("Microphone", "麦克风"))
                        .fontWeight(.medium)
                    Spacer()
                    Button(copy("Refresh", "刷新")) {
                        refreshPermissions()
                    }
                    .buttonStyle(.borderless)
                }

                VStack(alignment: .leading, spacing: 6) {
                    switch micPermission {
                    case .authorized:
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(copy("Granted — DoubleTapTalk can hear you", "已授权 —— DoubleTapTalk 可以使用麦克风"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let currentMicrophoneName, !currentMicrophoneName.isEmpty {
                            Text(currentMicrophoneName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    case .notDetermined:
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(copy("Not requested yet", "尚未请求权限"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(copy("macOS will ask for permission the first time you record.", "首次录音时 macOS 会弹出授权请求。"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(copy("Request Permission…", "请求权限…")) {
                                Task {
                                    _ = await MicrophonePermissionService.shared.requestPermission()
                                    refreshPermissions()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    case .denied, .restricted:
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(copy("Microphone permission denied — recording cannot start", "麦克风权限被拒绝 —— 无法开始录音"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(copy("Enable it in System Settings › Privacy & Security › Microphone. If the app doesn't appear, the toggle is likely already on — re-check after enabling.", "请在 系统设置 › 隐私与安全性 › 麦克风 中允许 DoubleTapTalk。若列表中找不到本应用，请先确认开关已开启，再回来点“刷新”。"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        Button(copy("Open System Settings", "打开系统设置")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    // Accessibility: the context reader is an optional second
                    // grant, surfaced here so a missing toggle is never a mystery.
                    if hasAccessibilityPermission {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(copy("Accessibility enabled — context reading active", "辅助功能已开启 —— 可读取环境上下文"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(copy("Accessibility not granted — app context unavailable", "辅助功能未开启 —— 无法读取应用上下文"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(copy("Required for reading existing text in fields and terminal output when polishing.", "润色时需要读取输入框现有文本与终端输出。"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(copy("Open System Settings", "打开系统设置")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text(copy("Permissions", "权限"))
            } footer: {
                Text(copy("Both grants are required for the full experience: the microphone for speech recognition, Accessibility for polishing context.", "完整体验需要两项授权：麦克风用于语音识别，辅助功能用于润色时的上下文读取。"))
                    .font(.caption)
            }

            // MARK: - Speech Recognition Section
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentColor)
                    Text(copy("Apple (On-Device)", "Apple（设备端）"))
                        .fontWeight(.medium)
                }
                Text(copy("On-device streaming recognition by Apple Speech. Live text appears while you speak — no API key, audio never leaves your Mac.", "由 Apple Speech 在设备端流式识别。说话时实时显示文字 —— 无需 API 密钥，音频不会离开您的 Mac。"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(copy("Language", "语言"), selection: $settings.language) {
                    Text(copy("Auto-detect", "自动检测")).tag("auto")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                }

                Text(copy("Auto follows your keyboard input method — Chinese IME → 中文识别, English keyboard → English.", "自动跟随您的键盘输入法 —— 中文输入法 → 中文识别，英文键盘 → 英文识别。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(copy("Speech Recognition", "语音识别"))
            }

            // MARK: - Continuous Dictation Section
            Section {
                HStack {
                    Text(copy("Segment idle threshold:", "段落静默阈值："))
                    Spacer()
                    Text(String(format: "%.1fs", settings.relayIdleThreshold))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Slider(value: $settings.relayIdleThreshold, in: 1.0...10.0, step: 0.5)
                        .frame(width: 150)
                }
                Text(copy("How long Apple must hear no new words before the segment is cut and inserted. Shorter = snappier, longer = fewer splits.", "Apple 在多长时间内没有听到新内容，即自动截断并插入当前段落。越短越跟手，越长切分越少。"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } header: {
                Text(copy("Continuous Dictation", "连续听写"))
            } footer: {
                Text(copy("Double-click Control to start — the microphone stays open and segments are recognized + inserted automatically as you pause. Backspace or a Control tap stops the session; the key still deletes normally. Each segment is uploaded for cloud transcription when enabled.", "双击 Control 开始 —— 麦克风保持开启，停顿后段落自动识别并插入。按退格键或单击 Control 结束会话；该键仍可正常删除。启用云端转写时，每个段落都会上传。"))
                    .font(.caption)
            }

            // MARK: - Usage Section
            Section {
                Text(copy("Double-click Control key to start recording. Single-click to stop. AI refinement applies automatically to every segment when enabled (including during continuous dictation).", "双击 Control 键开始录音，单击停止。启用后，AI 润色会自动应用到每个段落（包括连续听写期间）。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(copy("Usage", "使用说明"))
            }

            // MARK: - LLM Polishing Section
            Section {
                Toggle(isOn: $settings.llmEnabled) {
                    Text(copy("Enable AI Polishing", "启用 AI 润色"))
                }

                if settings.llmEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        // App-specific polish toggle
                        Toggle(isOn: $settings.useAppSpecificPolish) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(copy("App-specific polish (recommended)", "按应用定制润色（推荐）"))
                                    .fontWeight(.medium)
                                Text(copy("Automatically adapt polishing based on target app context", "根据目标应用上下文自动调整润色方式"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Accessibility permission warning
                        if !hasAccessibilityPermission && settings.useAppSpecificPolish {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(copy("Accessibility permission required for full context", "需要辅助功能权限以获得完整上下文"))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(copy("Grant permission to read existing text in fields and terminal output for better polishing.", "授权后可读取输入框现有文本与终端输出，使润色更贴合上下文。"))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Button(copy("Open System Settings", "打开系统设置")) {
                                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            Divider()
                        }

                        // Provider selection
                        Picker(copy("Provider", "服务商"), selection: $settings.llmProvider) {
                            ForEach(LLMProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: settings.llmProvider) { [settings] newValue in
                            settings.llmModel = newValue.defaultModel
                        }

                        // API Key input — secrets commit explicitly (Keychain
                        // writes are not per-keystroke); regular settings are live.
                        HStack {
                            if showLLMApiKey {
                                TextField(copy("API Key", "API 密钥"), text: $llmApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(copy("API Key", "API 密钥"), text: $llmApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(showLLMApiKey ? copy("Hide", "隐藏") : copy("Show", "显示")) {
                                showLLMApiKey.toggle()
                            }

                            Button(copy("Save", "保存")) {
                                settings.llmAPIKey = llmApiKeyInput.isEmpty ? nil : llmApiKeyInput
                            }
                            .disabled(llmApiKeyInput == (settings.llmAPIKey ?? ""))

                            if let saved = settings.llmAPIKey, !saved.isEmpty {
                                Button(copy("Clear", "清除")) {
                                    settings.llmAPIKey = nil
                                    llmApiKeyInput = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        if llmApiKeyInput != (settings.llmAPIKey ?? "") {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.orange)
                                Text(copy("Changes not saved — press Save", "更改尚未保存 —— 请点击“保存”"))
                                    .foregroundColor(.orange)
                            }
                            .font(.caption)
                        } else if let saved = settings.llmAPIKey, !saved.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(copy("API key saved", "API 密钥已保存"))
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                        }

                        // Custom API base URL for OpenAI-compatible APIs — live commit.
                        HStack {
                            TextField(copy("Custom API Base URL (optional)", "自定义 API Base URL（可选）"), text: $llmBaseURLInput)
                                .textFieldStyle(.roundedBorder)
                            if settings.llmBaseURL != nil {
                                Button(copy("Clear", "清除")) {
                                    settings.llmBaseURL = nil
                                    llmBaseURLInput = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onChange(of: llmBaseURLInput) { newValue in
                            settings.llmBaseURL = newValue.isEmpty ? nil : newValue
                        }

                        // Timeout setting
                        HStack {
                            Text(copy("Polishing Timeout:", "润色超时："))
                            Spacer()
                            Text(String(format: "%.1fs", settings.llmTimeout))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Slider(value: $settings.llmTimeout, in: 1.0...30.0, step: 1.0)
                                .frame(width: 150)
                        }

                        // Model name
                        HStack(spacing: 8) {
                            Text(copy("Model", "模型"))
                            TextField(copy("Model Name", "模型名称"), text: $settings.llmModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Temperature slider
                        HStack {
                            Text(copy("Temperature:", "温度："))
                            Spacer()
                            Text(String(format: "%.2f", settings.llmTemperature))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Slider(value: $settings.llmTemperature, in: 0.0...1.0, step: 0.1)
                                .frame(width: 150)
                        }

                        // System prompt (only shown when app-specific polish is disabled)
                        if !settings.useAppSpecificPolish {
                            Text(copy("System Prompt", "系统提示词"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $settings.llmSystemPrompt)
                                .frame(height: 100)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)

                            Text(copy("The system prompt defines how the AI should polish your text. Keep it concise.", "系统提示词定义 AI 应如何润色您的文本。请保持简洁。"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(copy("App-specific polish uses intelligent profiles for different apps. Custom system prompts are ignored when this is enabled.", "按应用定制润色会为不同应用使用智能配置。启用后自定义系统提示词将被忽略。"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text(copy("AI Text Polishing", "AI 文本润色"))
            } footer: {
                Text(settings.llmEnabled
                     ? copy("Applied automatically to each dictation segment when it completes; earlier segments are included as context for consistent terminology and style.", "每个听写段落完成后自动应用润色；前序段落会作为上下文，保证术语与风格一致。")
                     : copy("Optional: Use an LLM to improve transcription quality.", "可选：使用大语言模型提升转写质量。"))
                    .font(.caption)
            }

            // MARK: - Cloud Transcription Section
            Section {
                Toggle(isOn: $settings.asrEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy("Enable Cloud Transcription", "启用云端转写"))
                            .fontWeight(.medium)
                        Text(copy("After recording, the audio file is sent to an OpenAI-compatible ASR endpoint (e.g. Aliyun DashScope qwen3-asr-flash) for a more accurate result. Falls back to Apple on-device recognition on any failure.", "录音完成后，音频文件会发送到 OpenAI 兼容的 ASR 端点（如阿里云 DashScope qwen3-asr-flash）以获取更准确的结果。任何失败都会回退到 Apple 设备端识别。"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.asrEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        // Base URL — live commit
                        HStack {
                            TextField(copy("Base URL (OpenAI-compatible)", "Base URL（OpenAI 兼容）"), text: $asrBaseURLInput)
                                .textFieldStyle(.roundedBorder)
                            if settings.asrBaseURL != nil {
                                Button(copy("Clear", "清除")) {
                                    settings.asrBaseURL = nil
                                    asrBaseURLInput = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onChange(of: asrBaseURLInput) { newValue in
                            settings.asrBaseURL = newValue.isEmpty ? nil : newValue
                        }
                        Text(copy("Example: https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1 — leave empty to reuse the LLM base URL.", "示例：https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1 —— 留空则复用 LLM 的 Base URL。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // API key — explicit save
                        HStack {
                            if showASRApiKey {
                                TextField(copy("API Key", "API 密钥"), text: $asrApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField(copy("API Key", "API 密钥"), text: $asrApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(showASRApiKey ? copy("Hide", "隐藏") : copy("Show", "显示")) {
                                showASRApiKey.toggle()
                            }
                            Button(copy("Save", "保存")) {
                                settings.asrAPIKey = asrApiKeyInput.isEmpty ? nil : asrApiKeyInput
                            }
                            .disabled(asrApiKeyInput == (settings.asrAPIKey ?? ""))
                            if let saved = settings.asrAPIKey, !saved.isEmpty {
                                Button(copy("Clear", "清除")) {
                                    settings.asrAPIKey = nil
                                    asrApiKeyInput = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if asrApiKeyInput != (settings.asrAPIKey ?? "") {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.orange)
                                Text(copy("Changes not saved — press Save", "更改尚未保存 —— 请点击“保存”"))
                                    .foregroundColor(.orange)
                            }
                            .font(.caption)
                        }
                        Text(copy("Leave empty to reuse the LLM API key.", "留空则复用 LLM 的 API 密钥。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Model
                        TextField(copy("Model Name", "模型名称"), text: $settings.asrModel)
                            .textFieldStyle(.roundedBorder)
                        Text(copy("Default: qwen3-asr-flash (OpenAI-compatible mode; audio file limited to 10 MB / 5 min).", "默认：qwen3-asr-flash（OpenAI 兼容模式；音频文件限制为 10 MB / 5 分钟）。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Recording note
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.record")
                                .foregroundColor(.secondary)
                            Text(copy("Recordings are saved to Application Support/DoubleTapTalk/Recordings — see Recordings below to view usage, open the folder or delete them.", "录音保存在 Application Support/DoubleTapTalk/Recordings —— 可在下方“录音”节查看占用、打开文件夹或删除。"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text(copy("Cloud Transcription (OpenAI-compatible ASR)", "云端转写（OpenAI 兼容 ASR）"))
            } footer: {
                Text(settings.asrEnabled
                     ? copy("Live text during recording stays Apple on-device. The cloud result replaces the injected text only when the request succeeds.", "录音过程中的实时文本仍由 Apple 设备端提供；云端结果仅在请求成功时替换注入的文本。")
                     : copy("Optional: server-side transcription beats Apple on accuracy — requires an OpenAI-compatible ASR endpoint.", "可选：服务端转写在准确率上优于 Apple —— 需要 OpenAI 兼容的 ASR 端点。"))
                    .font(.caption)
            }

            // MARK: - Recordings Storage Section
            Section {
                HStack {
                    Text(copy("On disk:", "磁盘占用："))
                    Spacer()
                    Text("\(recordingStats.fileCount) file\(recordingStats.fileCount == 1 ? "" : "s") · \(recordingStats.formattedSize)")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Button(copy("Refresh", "刷新")) {
                        refreshRecordingStats()
                    }
                    .buttonStyle(.borderless)
                }
                HStack(spacing: 12) {
                    Button(copy("Open Folder", "打开文件夹")) {
                        RecordingStore.openInFinder(directory: RecordingStore.directory)
                    }
                    Button(role: .destructive) {
                        showDeleteRecordingsConfirm = true
                    } label: {
                        Text(copy("Delete All Recordings…", "删除全部录音…"))
                    }
                    .disabled(recordingStats.fileCount == 0)
                }
            } header: {
                Text(copy("Recordings", "录音"))
            } footer: {
                Text(copy("WAV recordings exist only when Cloud Transcription is enabled; they are kept on this Mac for upload and the newest 20 are kept automatically. Delete them here at any time.", "仅当启用云端转写时才会生成 WAV 录音；文件保存在本机用于上传，并自动保留最新的 20 个。可随时在此删除。"))
                    .font(.caption)
            }

            // MARK: - Reset Section
            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text(copy("Reset to Defaults…", "恢复默认设置…"))
                }
            } header: {
                Text(copy("Reset", "重置"))
            } footer: {
                Text(copy("Restores every setting — including API keys and cloud transcription — to their original values.", "将所有设置（包括 API 密钥与云端转写）恢复为默认值。"))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, idealWidth: 480)
        .confirmationDialog(copy("Delete all recordings?", "删除全部录音？"), isPresented: $showDeleteRecordingsConfirm) {
            Button(copy("Delete All Recordings", "删除全部录音"), role: .destructive) {
                RecordingStore.deleteAll(in: RecordingStore.directory)
                refreshRecordingStats()
            }
            Button(copy("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(copy("\(recordingStats.fileCount) file\(recordingStats.fileCount == 1 ? "" : "s") (\(recordingStats.formattedSize)) will be permanently deleted.",
                       "\(recordingStats.fileCount) 个文件（\(recordingStats.formattedSize)）将被永久删除。"))
        }
        .confirmationDialog(copy("Reset all settings?", "恢复所有默认设置？"), isPresented: $showResetConfirm) {
            Button(copy("Reset", "恢复默认"), role: .destructive) {
                settings.reset()
                llmApiKeyInput = ""
                asrApiKeyInput = ""
                asrBaseURLInput = ""
            }
            Button(copy("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(copy("All settings, including saved API keys and cloud transcription, will be restored to defaults.",
                       "所有设置（包括已保存的 API 密钥与云端转写）都将恢复为默认值。"))
        }
        .onAppear {
            llmApiKeyInput = settings.llmAPIKey ?? ""
            llmBaseURLInput = settings.llmBaseURL ?? ""
            asrApiKeyInput = settings.asrAPIKey ?? ""
            asrBaseURLInput = settings.asrBaseURL ?? ""
            refreshPermissions()
            refreshRecordingStats()
        }
        .onChange(of: settings.llmBaseURL) { newValue in
            llmBaseURLInput = newValue ?? ""
        }
        .onChange(of: settings.llmAPIKey) { newValue in
            llmApiKeyInput = newValue ?? ""
        }
        .onChange(of: settings.asrBaseURL) { newValue in
            asrBaseURLInput = newValue ?? ""
        }
        .onChange(of: settings.asrAPIKey) { newValue in
            asrApiKeyInput = newValue ?? ""
        }
    }

    private func refreshPermissions() {
        micPermission = MicrophonePermissionService.shared.permission()
        currentMicrophoneName = MicrophonePermissionService.shared.currentMicrophoneName()
        hasAccessibilityPermission = AccessibilityService.shared.hasAccessibilityPermission()
    }

    /// Recomputes the recordings usage shown in the Recordings section.
    private func refreshRecordingStats() {
        recordingStats = RecordingStore.stats(in: RecordingStore.directory)
    }
}