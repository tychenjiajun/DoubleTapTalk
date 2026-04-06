import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = VoiceKeySettings.shared
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    
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
                }
            } header: {
                Text("Usage")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 400)
        .onAppear {
            apiKeyInput = settings.apiKey ?? ""
        }
    }
}

#Preview {
    SettingsView()
}