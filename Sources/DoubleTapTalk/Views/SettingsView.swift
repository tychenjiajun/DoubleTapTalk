import SwiftUI
import Carbon

struct SettingsView: View {
    @StateObject private var settings = DoubleTapTalkSettings.shared
    
    // LLM Polishing state
    @State private var llmApiKeyInput: String = ""
    @State private var showLLMApiKey: Bool = false
    @State private var llmBaseURLInput: String = ""
    
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
            } header: {
                Text("Speech Recognition")
            }
            
            Section {
                Text("Double-click Control key to start recording. Single-click to stop without polish, double-click to stop with AI polish.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Reset to Defaults") {
                    settings.reset()
                    llmApiKeyInput = ""
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
                Text(settings.llmEnabled ? "Polished transcription will be injected instead of the raw ASR output." : "Optional: Use an LLM to improve transcription quality.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
        .onAppear {
            llmApiKeyInput = settings.llmAPIKey ?? ""
            llmBaseURLInput = settings.llmBaseURL ?? ""
            hasAccessibilityPermission = AccessibilityService.shared.hasAccessibilityPermission()
            currentMicrophoneName = MicrophonePermissionService.shared.currentMicrophoneName()
        }
        .onChange(of: settings.llmBaseURL) { newValue in
            llmBaseURLInput = newValue ?? ""
        }
        .onChange(of: settings.llmAPIKey) { newValue in
            llmApiKeyInput = newValue ?? ""
        }
    }
}