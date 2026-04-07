// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DoubleTapTalk",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DoubleTapTalk", targets: ["DoubleTapTalk"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DoubleTapTalk",
            path: "Sources/VoiceKey",
            sources: [
                "App/VoiceKeyApp.swift",
                "Backends/GroqBackend.swift",
                "Backends/LocalWhisperBackend.swift",
                "Backends/OpenAIWhisperBackend.swift",
                "Backends/DashscopeASRBackend.swift",
                "Models/ASRBackend.swift",
                "Models/LLMProvider.swift",
                "Models/PolishModels.swift",
                "Models/Settings.swift",
                "Services/AccessibilityService.swift",
                "Services/ASRService.swift",
                "Services/AudioRecorder.swift",
                "Services/HotkeyService.swift",
                "Services/KeychainService.swift",
                "Services/LLMService.swift",
                "Services/TextInjectionService.swift",
                "Views/SettingsView.swift",
                "Views/SettingsWindowController.swift",
                "Views/StatusBarController.swift"
            ],
            resources: [],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        )
        // Note: Unit tests require Xcode project due to XCTest framework dependencies
        // Tests are available in Tests/VoiceKeyTests/ and can be run via Xcode
    ]
)
