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
                "Backends/ContinuousDictationSession.swift",
                "Models/ASRSettings.swift",
                "Models/LLMProvider.swift",
                "Models/PipelineError.swift",
                "Models/PolishModels.swift",
                "Models/Settings.swift",
                "Services/AccessibilityService.swift",
                "Services/CloudTranscriptionService.swift",
                "Services/HotkeyService.swift",
                "Services/LLMService.swift",
                "Services/MicrophonePermissionService.swift",
                "Services/PolishProcessor.swift",
                "Services/RecordingFileWriter.swift",
                "Services/TextInjectionService.swift",
                "Views/SettingsView.swift",
                "Views/SettingsWindowController.swift",
                "Views/StatusBarController.swift",
                "Views/Overlay/OverlayMetrics.swift",
                "Views/Overlay/WaveformView.swift",
                "Views/Overlay/RecordingOverlayPanel.swift"
            ],
            resources: [],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
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
