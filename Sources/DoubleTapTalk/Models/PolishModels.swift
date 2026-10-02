import Foundation
import AppKit

// MARK: - Bundle ID Mappings (Single Source of Truth)

/// Centralized bundle ID mappings for all app categories
/// This is the single source of truth for app detection
struct BundleIDMappings {
    static let all: [String: [String]] = [
        // Development Tools
        "visual-studio-code": ["com.microsoft.VSCode"],
        "cursor": ["com.todesktop.230313mzl4w4u92", "io.cursor.Cursor"],
        "vscodium": ["com.vscodium"],
        "sublime-text": ["com.sublimetext.4", "com.sublimetext.3", "com.sublimetext.2"],
        "intellij-idea": ["com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.intellij"],
        "pycharm": ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"],
        "webstorm": ["com.jetbrains.webstorm"],
        "phpstorm": ["com.jetbrains.phpstorm"],
        "rubymine": ["com.jetbrains.rubymine"],
        "goland": ["com.jetbrains.goland"],
        "clion": ["com.jetbrains.clion"],
        "rider": ["com.jetbrains.rider"],
        "rustrover": ["com.jetbrains.rustrover"],
        "android-studio": ["com.google.android.studio"],
        "xcode": ["com.apple.dt.Xcode"],
        "github-desktop": ["com.github.GitHubDesktop"],
        "sourcetree": ["com.torusknot.SourceTreeNotMAS"],
        "docker-desktop": ["com.docker.docker"],
        "postman": ["com.postmanlabs.mac"],
        "nova": ["com.panic.Nova"],
        "textmate": ["com.macromates.TextMate.preview"],
        "atom": ["com.github.atom"],
        "eclipse": ["org.eclipse.platform.ide", "epp.package.java"],
        "zed": ["dev.zed.Zed"],
        
        // Browsers
        "google-chrome": ["com.google.Chrome"],
        "firefox": ["org.mozilla.firefox"],
        "brave-browser": ["com.brave.Browser"],
        "microsoft-edge": ["com.microsoft.edgemac", "com.microsoft.edge"],
        "arc": ["company.thebrowser.Browser"],
        "opera": ["com.operasoftware.Opera", "com.opera.Stable"],
        "vivaldi": ["com.vivaldi.Vivaldi"],
        "safari": ["com.apple.Safari"],
        "qq-browser": ["com.tencent.qqbrowserappmac"],
        "maxthon": ["com.maxthon.mac.Maxthon"],
        "waterfox": ["net.waterfox.waterfox"],
        "otter-browser": ["org.otter-browser.otter-browser"],
        
        // Communication & Chat
        "slack": ["com.tinyspeck.slackmacgap"],
        "discord": ["com.hnc.Discord"],
        "telegram": ["ru.keepcoder.Telegram"],
        "whatsapp": ["net.whatsapp.WhatsApp", "com.whatsapp.Mac"],
        "signal": ["org.whispersystems.signal-desktop"],
        "wechat": ["com.tencent.xinWeChat", "com.tencent.wechat"],
        "qq": ["com.tencent.qq"],
        "wework": ["com.tencent.WeWorkMac"],
        "dingtalk": ["com.laiwang.DingTalk", "dd.work.exclusive4aliding"],
        "line": ["jp.naver.line.mac"],
        "skype": ["com.skype.skype"],
        "kakao-talk": ["com.kakao.KakaoTalkMac"],
        "cherry-studio": ["com.kangfenmao.CherryStudio"],
        "atlassian-companion": ["com.companion.app", "com.electron.companion"],
        "riot-chat": ["com.riotgames.RiotChat"],
        "messenger": ["com.facebook.archon"],
        "teams": ["com.microsoft.teams2"],
        
        // Email
        "mail": ["com.apple.mail", "com.apple.MobileSMS"],
        "outlook": ["com.microsoft.Outlook"],
        "thunderbird": ["org.mozilla.thunderbird"],
        
        // Productivity & Notes
        "notion": ["notion.id"],
        "obsidian": ["md.obsidian"],
        "onenote": ["com.microsoft.onenote.mac"],
        "evernote": ["com.evernote.Evernote"],
        "bear": ["net.shinyfrog.bear"],
        "linear": ["com.linear"],
        "todoist": ["com.todoist.mac.Todoist"],
        "things": ["com.culturedcode.things"],
        "pages": ["com.apple.iWork.Pages", "com.apple.Pages"],
        
        // Terminal
        "iterm2": ["com.googlecode.iterm2"],
        "warp": ["dev.warp.Warp-Stable", "io.warp.Warp"],
        "hyper": ["co.zeit.hyper"],
        "terminal": ["com.apple.Terminal"],
        "zsh": ["com.apple.Terminal"],
        
        // Trading Platforms
        "tonghuashun": ["cn.com.10jqka.macstockPro"],
        "dazhihui": ["cn.com.gw.DZH"],
        "futuniuniu": ["cn.futu.Niuniu", "com.futuhuwai.stockpro"],
        "eastmoney": ["com.emmac.mac"],
        "jd-finance": ["com.jdjr.huangjin"],
        "schwab": ["com.schwab.SchwabMobile"],
        "etrade": ["com.etrade.mobile.pro"],
        "td-ameritrade": ["com.tdameritrade.desktop"],
        "ibkr": ["com.interactivebrokers.TWS"]
    ]
    
    /// Get all bundle IDs for a category
    static func get(for category: String) -> [String] {
        return all[category] ?? []
    }
    
    /// Get all bundle IDs across all categories
    static func getAll() -> Set<String> {
        return Set(all.values.flatMap { $0 })
    }
    
    /// Check if a bundle ID belongs to a category
    static func contains(bundleID: String, category: String) -> Bool {
        return get(for: category).contains(where: { bundleID.hasPrefix($0) })
    }
}

// MARK: - Polish Profile Detection

enum PolishProfile: String, CaseIterable, Codable {
    case terminal
    case codeComment
    case chatMessaging
    case emailFormal
    case searchQuery
    case codeEditor
    case tradingTerminal
    case general
    
    static func detect(from context: AppContext) -> PolishProfile {
        guard let bundleID = context.bundleID else { return .general }
        
        // Terminal apps
        if context.isTerminal { return .terminal }
        
        // Code editors and IDEs - check focused element for comment detection
        if context.isCodeEditor {
            // Code comment: textarea with comment-like context or specific element role
            let role = context.focusedElementRole ?? ""
            let title = context.windowTitle?.lowercased() ?? ""
            
            // Detect comment areas: textarea in code editor, or window title suggests comments
            if role == "AXTextArea" || title.contains("comment") || title.contains("review") {
                return .codeComment
            }
            return .codeEditor
        }
        
        // Browser URL/search bar
        if context.isBrowser && context.focusedElementRole == "AXTextField" {
            return .searchQuery
        }
        
        // Chat/messaging apps - comprehensive list using centralized mappings
        let chatCategories = ["slack", "discord", "telegram", "whatsapp", "signal", "wechat", 
                              "qq", "wework", "dingtalk", "line", "skype", "kakao-talk",
                              "cherry-studio", "atlassian-companion", "riot-chat", "messenger", "teams"]
        for category in chatCategories {
            if BundleIDMappings.contains(bundleID: bundleID, category: category) {
                return .chatMessaging
            }
        }
        
        // Trading/stock apps
        if context.isTradingApp {
            return .tradingTerminal
        }
        
        // Email apps
        if BundleIDMappings.contains(bundleID: bundleID, category: "mail") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "outlook") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "thunderbird") {
            return .emailFormal
        }
        
        // Check for Gmail in browser via window title
        let title = context.windowTitle?.lowercased() ?? ""
        if context.isBrowser && (title.contains("gmail") || title.contains("compose")) {
            return .emailFormal
        }
        
        // Note-taking / documentation apps
        let noteCategories = ["notion", "obsidian", "onenote", "evernote", "bear", 
                              "linear", "todoist", "pages"]
        for category in noteCategories {
            if BundleIDMappings.contains(bundleID: bundleID, category: category) {
                return .general
            }
        }
        
        return .general
    }
}

// MARK: - App Context

/// Captures information about the target application where text will be injected
struct AppContext {
    let appName: String
    let bundleID: String?
    let isTerminal: Bool
    let isBrowser: Bool
    let isCodeEditor: Bool
    let isTradingApp: Bool
    let focusedElementRole: String?  // AXRole of focused element (e.g., "AXTextField", "AXTextArea")
    let windowTitle: String?
    let focusedElementValue: String? // Current text in the focused field
    
    /// Primary initializer using NSRunningApplication
    init(app: NSRunningApplication, focusedElementInfo: FocusedElementInfo?) {
        self.appName = app.localizedName ?? "Unknown"
        self.bundleID = app.bundleIdentifier
        
        // Detect app types using centralized bundle ID mappings
        self.isTerminal = Self.isTerminalApp(bundleID: app.bundleIdentifier, appName: app.localizedName ?? "")
        self.isBrowser = Self.isBrowserApp(bundleID: app.bundleIdentifier)
        self.isCodeEditor = Self.isCodeEditorApp(bundleID: app.bundleIdentifier, appName: app.localizedName ?? "")
        self.isTradingApp = Self.isTradingApp(bundleID: app.bundleIdentifier, appName: app.localizedName ?? "")
        
        // Use provided focusedElementInfo or capture it via Accessibility API
        if let info = focusedElementInfo {
            self.focusedElementRole = info.role
            self.focusedElementValue = info.value
        } else {
            // Try to capture it automatically (requires accessibility permission)
            let captured = AccessibilityService.shared.captureFocusedElementInfo(from: app)
            self.focusedElementRole = captured?.role
            self.focusedElementValue = captured?.value
        }
        
        self.windowTitle = Self.getWindowTitle(for: app)
    }
    
    /// Test-friendly initializer for unit testing
    init(
        appName: String,
        bundleID: String?,
        isTerminal: Bool,
        isBrowser: Bool,
        isCodeEditor: Bool,
        isTradingApp: Bool,
        focusedElementRole: String?,
        windowTitle: String?,
        focusedElementValue: String?
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.isTerminal = isTerminal
        self.isBrowser = isBrowser
        self.isCodeEditor = isCodeEditor
        self.isTradingApp = isTradingApp
        self.focusedElementRole = focusedElementRole
        self.windowTitle = windowTitle
        self.focusedElementValue = focusedElementValue
    }
    
    /// Check if app is a terminal using centralized mappings + name matching
    private static func isTerminalApp(bundleID: String?, appName: String) -> Bool {
        guard let bundleID = bundleID else {
            return Self.terminalNameMatches(appName)
        }
        
        // Check centralized mappings first
        if BundleIDMappings.contains(bundleID: bundleID, category: "terminal") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "iterm2") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "warp") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "hyper") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "zsh") {
            return true
        }
        
        // Fallback to name matching
        return Self.terminalNameMatches(appName)
    }
    
    private static func terminalNameMatches(_ appName: String) -> Bool {
        let terminalNames = ["terminal", "iterm", "warp", "zsh", "bash", "fish", "hyper"]
        return terminalNames.contains(where: { appName.lowercased().contains($0) })
    }
    
    /// Check if app is a browser using centralized mappings + name matching
    private static func isBrowserApp(bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        
        // Check centralized mappings
        if BundleIDMappings.contains(bundleID: bundleID, category: "google-chrome") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "firefox") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "brave-browser") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "microsoft-edge") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "arc") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "opera") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "safari") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "vivaldi") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "qq-browser") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "maxthon") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "waterfox") {
            return true
        }
        
        // Fallback to name matching
        let browserNames = ["chrome", "firefox", "safari", "edge", "brave", "opera", "arc", "browser"]
        return browserNames.contains(where: { bundleID.lowercased().contains($0) })
    }
    
    /// Get window title using Accessibility API
    private static func getWindowTitle(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        
        // Try to get the focused window
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) != .success || windowRef == nil {
            // Fallback: try to get the first window
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement],
                  let firstWindow = windows.first else {
                return nil
            }
            windowRef = firstWindow
        }
        
        // Get the window title
        var titleRef: CFTypeRef?
        guard let rawWindow = windowRef,
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(rawWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return nil
        }
        
        return title.isEmpty ? nil : title
    }
    
    /// Check if app is a code editor using centralized mappings + name matching
    private static func isCodeEditorApp(bundleID: String?, appName: String) -> Bool {
        guard let bundleID = bundleID else {
            return Self.codeEditorNameMatches(appName)
        }
        
        // Check centralized mappings
        if BundleIDMappings.contains(bundleID: bundleID, category: "visual-studio-code") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "cursor") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "vscodium") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "sublime-text") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "intellij-idea") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "pycharm") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "webstorm") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "phpstorm") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "rubymine") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "goland") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "clion") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "rider") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "rustrover") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "xcode") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "zed") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "nova") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "textmate") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "eclipse") {
            return true
        }
        
        // Fallback to name matching
        return Self.codeEditorNameMatches(appName)
    }
    
    private static func codeEditorNameMatches(_ appName: String) -> Bool {
        let codeEditorNames = [
            "vscode", "visual studio code", "cursor", "zed", "xcode",
            "intellij", "pycharm", "phpstorm", "rubymine", "clion",
            "rider", "rustrover", "webstorm", "goland", "eclipse",
            "sublime", "atom", "nova", "textmate", "vim", "emacs"
        ]
        return codeEditorNames.contains(where: { appName.lowercased().contains($0) })
    }
    
    /// Check if app is a trading/stock platform using centralized mappings + name matching
    private static func isTradingApp(bundleID: String?, appName: String) -> Bool {
        guard let bundleID = bundleID else {
            return Self.tradingNameMatches(appName)
        }
        
        // Check centralized mappings
        if BundleIDMappings.contains(bundleID: bundleID, category: "tonghuashun") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "dazhihui") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "futuniuniu") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "eastmoney") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "jd-finance") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "schwab") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "etrade") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "td-ameritrade") ||
           BundleIDMappings.contains(bundleID: bundleID, category: "ibkr") {
            return true
        }
        
        // Fallback to name matching
        return Self.tradingNameMatches(appName)
    }
    
    private static func tradingNameMatches(_ appName: String) -> Bool {
        let tradingNames = [
            "stock", "trader", "证券", "股票", "理财", "基金",
            "同花顺", "大智慧", "富途", "东财", "东方财富", "老虎", "盈透",
            "security", "invest", "broker", "trade", "stocks"
        ]
        return tradingNames.contains(where: { appName.lowercased().contains($0) })
    }
}

// MARK: - Focused Element Info

/// Information about the currently focused UI element
struct FocusedElementInfo {
    let role: String
    let value: String?
}

// MARK: - Polish Context

/// Context for generating profile-specific system prompts
struct PolishContext {
    let targetApp: AppContext
    let existingText: String?
    let conversationHint: String?
    let userLocale: String  // e.g., "en", "en_US", "zh"
    /// Earlier segments of the same dictation session (asr/refinement results),
    /// so the model keeps terminology + style consistent and never repeats them.
    var previousSegments: [String] = []
}

// MARK: - Shared Prompt Sections

/// Reusable language preservation guard (CRITICAL — shared by every profile)
/// Kept deliberately compact: the wrong/right pair is what models actually learn from.
private let languagePreservationSection = """
⚠️ NEVER translate or transliterate: English stays English, 中文 stays 中文 — keep every script exactly as spoken.
Wrong: "check logs" → 查看日志. Right: "check logs" → check logs; "查看日志" → 查看日志.
"""

/// Reusable base instruction
private let baseInstruction = "Output ONLY the polished text. No explanations, quotes, or preamble."

/// Builds a compact profile prompt: shared base + anti-translation guard +
/// one unique rule line (economy — mirrors the ~200-token refinement style).
private func buildPrompt(role: String, rule: String, contextHint: String) -> String {
    return """
    \(baseInstruction)
    \(role)
    \(languagePreservationSection)
    \(rule)
    \(contextHint)
    """
}

/// Builds a compact "earlier dictation" hint from the session's previous
/// segments (capped: last 8 segments, 120 chars each) so prompts stay small.
private func buildHistoryHint(_ segments: [String]) -> String {
    let recent = segments.suffix(8)
    guard !recent.isEmpty else { return "" }
    let lines = recent.enumerated()
        .map { "\($0.offset + 1)) \(String($0.element.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)))" }
        .joined(separator: "\n")
    return "\n\nEarlier dictation (same session) — keep terminology and style consistent, do NOT repeat any of it:\n\(lines)"
}

/// Build context hint from existing text, conversation hint and previous segments.
///
/// Deliberately NOT fenced with ``` and explicitly labelled as context: measured
/// on liquid/lfm-2.5-2.6b:free, fenced context made the model return the field's
/// existing text instead of the new utterance (1 in 5 samples); these labels
/// fixed it (5/5). See Tests/VoiceKeyTests/RefinementPromptEvalTests.swift.
private func buildContextHint(existingText: String?, conversationHint: String?, previousSegments: [String]) -> String {
    let base: String
    switch (existingText, conversationHint) {
    case (let text?, _) where !(text.isEmpty):
        let label = "Already typed in the field (context only — your output must contain ONLY the new utterance):"
        if let hint = conversationHint, !hint.isEmpty {
            base = "\n\n\(label)\n\(String(text.suffix(200)))\n\nRecent screen content (context only — never repeat it):\n\(hint)"
        } else {
            base = "\n\n\(label)\n\(String(text.suffix(200)))"
        }
    case (_, let hint?) where !(hint.isEmpty):
        base = "\n\nRecent screen content (context only — never repeat it):\n\(hint)"
    default:
        base = ""
    }
    return base + buildHistoryHint(previousSegments)
}

extension PolishProfile {
    
    /// Detect what shell/command is currently running from terminal prompt
    private func detectTerminalBinary(from context: String?) -> String? {
        guard let context = context, !context.isEmpty else { return nil }
        
        // Look for common shell prompts and patterns
        let lines = context.components(separatedBy: "\n")
        let lastLine = lines.last ?? ""
        
        // Check for zsh, bash, fish prompts
        if lastLine.contains("% ") || lastLine.contains("$ ") {
            if lastLine.hasPrefix("➜") || lastLine.hasPrefix("❯") || lastLine.contains("@") {
                // Likely zsh with powerlevel10k or similar
                return "zsh"
            } else if lastLine.lowercased().contains("bash") || lastLine.lowercased().contains("root@") {
                return "bash"
            } else if lastLine.lowercased().contains("fish") {
                return "fish"
            }
            return "shell"  // Generic shell
        }
        
        // Check if we're inside a specific tool
        if lastLine.contains("(git)") || lastLine.contains("(main)") || lastLine.contains("dev:") {
            return "git"  // Inside git repo
        }
        
        // Check for coding agent patterns
        if lastLine.contains("🤖") || lastLine.contains("agent") || lastLine.contains("AI>") {
            return "coding-agent"
        }
        
        // Try to extract command name from partial input
        let trimmed = lastLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 0 && !trimmed.contains(" ") {
            // Single word looks like a command being typed
            return trimmed
        }
        
        return nil
    }
    
    func systemPrompt(context: PolishContext) -> String {
        let contextHint = buildContextHint(existingText: context.existingText, conversationHint: context.conversationHint, previousSegments: context.previousSegments)
        
        switch self {
        case .terminal:
            let currentBinary = detectTerminalBinary(from: context.conversationHint)
            return buildPrompt(
                role: "You are polishing speech-to-text for terminal input. Shell: \(currentBinary ?? "unknown").",
                rule: "Terminal: imperative verbs (run/build/test) → command phrasing; questions stay natural; no backticks or markdown.",
                contextHint: contextHint
            )
            
        case .codeComment:
            return buildPrompt(
                role: "You are polishing speech-to-text for a code comment.",
                rule: "Code comment: concise technical comment; remove filler words only; no // or # markers; preserve identifiers, variable names, acronyms.",
                contextHint: contextHint
            )
            
        case .codeEditor:
            return buildPrompt(
                role: "You are polishing speech-to-text for a code editor (docs, README, commit messages).",
                rule: "Code editor: fix grammar and punctuation only; remove filler words (um, uh); keep concise; preserve identifiers, paths, acronyms.",
                contextHint: contextHint
            )
            
        case .tradingTerminal:
            return buildPrompt(
                role: "You are polishing speech-to-text for trading terminal input (stock codes, order parameters).",
                rule: "Trading: explicit orders → 'BUY 100 TSLA MARKET'; 买入→BUY, 卖出→SELL, 市价→MARKET, 限价→LIMIT; keep codes, prices, quantities exact.",
                contextHint: contextHint
            )
            
        case .chatMessaging:
            return buildPrompt(
                role: "You are polishing speech-to-text for a chat message (Slack, Discord, WhatsApp).",
                rule: "Chat: conversational and natural; light punctuation; remove filler words (um, uh); NEVER delete casual slang or expressions (lol, haha, omg, btw) — keep tone, humor, sarcasm, emojis.",
                contextHint: contextHint
            )
            
        case .emailFormal:
            return buildPrompt(
                role: "You are polishing speech-to-text for a professional email.",
                rule: "Email: full grammatical sentences, proper punctuation, professional tone; expand contractions (don't → do not); keep names, emails, dates exact.",
                contextHint: contextHint
            )
            
        case .searchQuery:
            return buildPrompt(
                role: "You are polishing speech-to-text for a search query.",
                rule: "Search: essential keywords only; remove articles, prepositions, filler words; no trailing punctuation; keep technical terms, product names, versions exact.",
                contextHint: contextHint
            )
            
        case .general:
            return buildPrompt(
                role: "You are polishing speech-to-text into clean readable text.",
                rule: "General: fix grammar and punctuation; strip filler words (um, uh, like, you know, I mean) wherever they appear; preserve intent and voice; keep names, places, numbers, terms exact.",
                contextHint: contextHint
            )
        }
    }
}
