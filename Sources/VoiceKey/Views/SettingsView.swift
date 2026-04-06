import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = DoubleTapTalkSettings.shared
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    
    // LLM Polishing state
    @State private var llmApiKeyInput: String = ""
    @State private var showLLMApiKey: Bool = false
    @State private var llmBaseURLInput: String = ""
    
    var body: some View {
        Form {
            Section {
                Picker("Backend", selection: $settings.backendType) {
                    ForEach(ASRBackendType.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .onChange(of: settings.backendType) { newValue in
                    settings.apiURL = newValue.defaultURL
                    apiKeyInput = settings.apiKey ?? ""
                }
            } header: {
                Text("ASR Service")
            }
            
            Section {
                if settings.backendType.requiresAPIKey {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(showAPIKey ? "Hide" : "Show") {
                            showAPIKey.toggle()
                        }
                        
                        Button("Save") {
                            settings.apiKey = apiKeyInput
                        }
                    }
                    
                    if settings.apiKey != nil && !settings.apiKey!.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key saved in Keychain")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                TextField("API URL", text: $settings.apiURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.backendType.requiresAPIKey && settings.backendType != .local)
            } header: {
                Text("Configuration")
            }
            
            Section {
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
                
                TextField("Model", text: $settings.model)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Transcription")
            }
            
            Section {
                Text("Hold Right Option key to record audio. Release to transcribe and type the result into the frontmost app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Reset to Defaults") {
                    settings.reset()
                    apiKeyInput = ""
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
                        
                        // System prompt
                        TextEditor(text: $settings.llmSystemPrompt)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                        
                        Text("The system prompt defines how the AI should polish your text. Keep it concise.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        .frame(width: 500, height: 550)
        .onAppear {
            apiKeyInput = settings.apiKey ?? ""
            llmApiKeyInput = settings.llmAPIKey ?? ""
            llmBaseURLInput = settings.llmBaseURL ?? ""
        }
        .onChange(of: settings.llmBaseURL) { newValue in
            llmBaseURLInput = newValue ?? ""
        }
        .onChange(of: settings.llmAPIKey) { newValue in
            llmApiKeyInput = newValue ?? ""
        }
    }
}