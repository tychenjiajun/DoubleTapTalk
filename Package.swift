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
            path: "Sources/DoubleTapTalk",
            sources: [
                "App/DoubleTapTalkApp.swift",
                "Backends/AppleSpeechBackend.swift",
                "Backends/DashscopeASRBackend.swift",
                "Backends/LocalWhisperBackend.swift",
                "Backends/OpenAIWhisperBackend.swift",
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
                "Services/MicrophonePermissionService.swift",
                "Services/PolishProcessor.swift",
                "Services/TextInjectionService.swift",
                "Views/SettingsView.swift",
                "Views/SettingsWindowController.swift",
                "Views/StatusBarController.swift",
                "Views/Overlay/OverlayMetrics.swift",
                "Views/Overlay/WaveformAnimator.swift",
                "Views/Overlay/WaveformView.swift",
                "Views/Overlay/RecordingOverlayPanel.swift"
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
        ),
        .testTarget(
            name: "DoubleTapTalkTests",
            dependencies: ["DoubleTapTalk"],
            path: "Tests/VoiceKeyTests"
        )
    ]
)
