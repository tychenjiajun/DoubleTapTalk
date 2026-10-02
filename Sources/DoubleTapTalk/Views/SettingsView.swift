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

    // Accessibility and microphone info state
    @State private var hasAccessibilityPermission: Bool = AccessibilityService.shared.hasAccessibilityPermission()
    @State private var currentMicrophoneName: String? = nil
    
    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.accentColor)
                    Text("Apple (On-Device)")
                        .fontWeight(.medium)
                }
                Text("On-device streaming recognition by Apple Speech. Live text appears while you speak — no API key, audio never leaves your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Language", selection: $settings.language) {
                    Text("Auto-detect").tag("auto")
                    Text("English").tag("en")
                    Text("Chinese").tag("zh")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                }
                
                Text("Auto follows your keyboard input method — Chinese IME → 中文识别, English keyboard → English.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Speech Recognition")
            }
            
            // MARK: - Continuous Dictation Section
            Section {
                HStack {
                    Text("Segment idle threshold:")
                    Spacer()
                    Text(String(format: "%.1fs", settings.relayIdleThreshold))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Slider(value: $settings.relayIdleThreshold, in: 1.0...10.0, step: 0.5)
                        .frame(width: 150)
                }
                Text("How long Apple must hear no new words before the segment is cut and inserted. Shorter = snappier, longer = fewer splits.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } header: {
                Text("Continuous Dictation")
            } footer: {
                Text("Double-click Control to start — the microphone stays open and segments are recognized + inserted automatically as you pause. Backspace or a Control tap stops the session; the key still deletes normally. Each segment is uploaded for cloud transcription when enabled.")
                    .font(.caption)
            }

            Section {
                Text("Double-click Control key to start recording. Single-click to stop. AI refinement applies automatically to every segment when enabled (including during continuous dictation).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Reset to Defaults") {
                    settings.reset()
                    llmApiKeyInput = ""
                    asrApiKeyInput = ""
                    asrBaseURLInput = ""
                }
            } header: {
                Text("Usage")
            }
            
            // MARK: - LLM Polishing Section
            Section {
                Toggle(isOn: $settings.llmEnabled) {
                    Text("Enable AI Polishing")
                }
                
                if settings.llmEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        // App-specific polish toggle
                        Toggle(isOn: $settings.useAppSpecificPolish) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("App-specific polish (recommended)")
                                    .fontWeight(.medium)
                                Text("Automatically adapt polishing based on target app context")
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
                                    Text("Accessibility permission required for full context")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text("Grant permission to read existing text in fields and terminal output for better polishing.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Button("Open System Preferences") {
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
                        } else if hasAccessibilityPermission {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Accessibility enabled — context reading active")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Divider()
                        }
                        // Provider selection
                        Picker("Provider", selection: $settings.llmProvider) {
                            ForEach(LLMProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: settings.llmProvider) { [settings] newValue in
                            settings.llmModel = newValue.defaultModel
                        }
                        
                        // API Key input
                        HStack {
                            if showLLMApiKey {
                                TextField("API Key", text: $llmApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("API Key", text: $llmApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button(showLLMApiKey ? "Hide" : "Show") {
                                showLLMApiKey.toggle()
                            }
                            
                            Button("Save") {
                                settings.llmAPIKey = llmApiKeyInput
                            }
                        }
                        
                        if settings.llmAPIKey != nil && !settings.llmAPIKey!.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("API Key saved")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Custom API base URL for OpenAI-compatible APIs
                        HStack {
                            TextField("Custom API Base URL (optional)", text: $llmBaseURLInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                settings.llmBaseURL = llmBaseURLInput.isEmpty ? nil : llmBaseURLInput
                            }
                            if settings.llmBaseURL != nil {
                                Button("Clear") {
                                    settings.llmBaseURL = nil
                                    llmBaseURLInput = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        
                        // Timeout setting
                        HStack {
                            Text("Polishing Timeout:")
                            Spacer()
                            Text(String(format: "%.1fs", settings.llmTimeout))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Slider(value: $settings.llmTimeout, in: 1.0...30.0, step: 1.0)
                                .frame(width: 150)
                        }
                        
                        // Model name
                        TextField("Model Name", text: $settings.llmModel)
                            .textFieldStyle(.roundedBorder)
                        
                        // Temperature slider
                        HStack {
                            Text("Temperature:")
                            Spacer()
                            Text(String(format: "%.2f", settings.llmTemperature))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Slider(value: $settings.llmTemperature, in: 0.0...1.0, step: 0.1)
                                .frame(width: 150)
                        }
                        
                        // System prompt (only shown when app-specific polish is disabled)
                        if !settings.useAppSpecificPolish {
                            TextEditor(text: $settings.llmSystemPrompt)
                                .frame(height: 100)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                            
                            Text("The system prompt defines how the AI should polish your text. Keep it concise.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("App-specific polish uses intelligent profiles for different apps. Custom system prompts are ignored when this is enabled.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("AI Text Polishing")
            } footer: {
                Text(settings.llmEnabled ? "Applied automatically to each dictation segment when it completes; earlier segments are included as context for consistent terminology and style." : "Optional: Use an LLM to improve transcription quality.")
                    .font(.caption)
            }

            // MARK: - Cloud Transcription Section
            Section {
                Toggle(isOn: $settings.asrEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Cloud Transcription")
                            .fontWeight(.medium)
                        Text("After recording, the audio file is sent to an OpenAI-compatible ASR endpoint (e.g. Aliyun DashScope qwen3-asr-flash) for a more accurate result. Falls back to Apple on-device recognition on any failure.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.asrEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        // Base URL
                        HStack {
                            TextField("Base URL (OpenAI-compatible)", text: $asrBaseURLInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                settings.asrBaseURL = asrBaseURLInput.isEmpty ? nil : asrBaseURLInput
                            }
                            if settings.asrBaseURL != nil {
                                Button("Clear") {
                                    settings.asrBaseURL = nil
                                    asrBaseURLInput = ""
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Text("Example: https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1 — leave empty to reuse the LLM base URL.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // API key
                        HStack {
                            if showASRApiKey {
                                TextField("API Key", text: $asrApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("API Key", text: $asrApiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(showASRApiKey ? "Hide" : "Show") {
                                showASRApiKey.toggle()
                            }
                            Button("Save") {
                                settings.asrAPIKey = asrApiKeyInput.isEmpty ? nil : asrApiKeyInput
                            }
                        }
                        Text("Leave empty to reuse the LLM API key.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Model
                        TextField("Model Name", text: $settings.asrModel)
                            .textFieldStyle(.roundedBorder)
                        Text("Default: qwen3-asr-flash (OpenAI-compatible mode; audio file limited to 10 MB / 5 min).")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Recording note
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.record")
                                .foregroundColor(.secondary)
                            Text("Recordings are saved to Application Support/DoubleTapTalk/Recordings — see Recordings below to view usage, open the folder or delete them.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Cloud Transcription (OpenAI-compatible ASR)")
            } footer: {
                Text(settings.asrEnabled ? "Live text during recording stays Apple on-device. The cloud result replaces the injected text only when the request succeeds." : "Optional: server-side transcription beats Apple on accuracy — requires an OpenAI-compatible ASR endpoint.")
                    .font(.caption)
            }

            // MARK: - Recordings Storage Section
            Section {
                HStack {
                    Text("On disk:")
                    Spacer()
                    Text("\(recordingStats.fileCount) file\(recordingStats.fileCount == 1 ? "" : "s") · \(recordingStats.formattedSize)")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Button("Refresh") {
                        refreshRecordingStats()
                    }
                    .buttonStyle(.borderless)
                }
                HStack(spacing: 12) {
                    Button("Open Folder") {
                        RecordingStore.openInFinder(directory: RecordingStore.directory)
                    }
                    Button(role: .destructive) {
                        showDeleteRecordingsConfirm = true
                    } label: {
                        Text("Delete All Recordings…")
                    }
                    .disabled(recordingStats.fileCount == 0)
                }
            } header: {
                Text("Recordings")
            } footer: {
                Text("WAV recordings exist only when Cloud Transcription is enabled; they are kept on this Mac for upload and the newest 20 are kept automatically. Delete them here at any time.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
        .confirmationDialog("Delete all recordings?", isPresented: $showDeleteRecordingsConfirm) {
            Button("Delete All Recordings", role: .destructive) {
                RecordingStore.deleteAll(in: RecordingStore.directory)
                refreshRecordingStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(recordingStats.fileCount) file\(recordingStats.fileCount == 1 ? "" : "s") (\(recordingStats.formattedSize)) will be permanently deleted.")
        }
        .onAppear {
            llmApiKeyInput = settings.llmAPIKey ?? ""
            llmBaseURLInput = settings.llmBaseURL ?? ""
            asrApiKeyInput = settings.asrAPIKey ?? ""
            asrBaseURLInput = settings.asrBaseURL ?? ""
            hasAccessibilityPermission = AccessibilityService.shared.hasAccessibilityPermission()
            currentMicrophoneName = MicrophonePermissionService.shared.currentMicrophoneName()
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

    /// Recomputes the recordings usage shown in the Recordings section.
    private func refreshRecordingStats() {
        recordingStats = RecordingStore.stats(in: RecordingStore.directory)
    }
}
