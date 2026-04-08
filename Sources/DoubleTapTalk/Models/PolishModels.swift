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
            self.focusedElementRole = captured.role
            self.focusedElementValue = captured.value
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
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
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
        // Build locale with region for better localization
        let locale = context.userLocale
        
        // Build context hints gracefully - handle cases where app doesn't share text
        let contextHint: String
        switch (context.existingText, context.conversationHint) {
        case (let text?, _) where !(text.isEmpty):
            // Both existing text and conversation hint available
            if let hint = context.conversationHint, !hint.isEmpty {
                contextHint = "\n\nExisting text in field (last 300 chars):\n```\n\(String(text.suffix(300)))\n```\n\nRecent context:\n```\n\(hint)\n```\n\n"
            } else {
                contextHint = "\n\nExisting text in field (last 300 chars):\n```\n\(String(text.suffix(300)))\n```\n\n"
            }
        case (_, let hint?) where !(hint.isEmpty):
            // Only conversation hint available (e.g., terminal output)
            contextHint = "\n\nRecent context for reference:\n```\n\(hint)\n```\n\n"
        case (nil, nil), (_, _):
            // No context available — prompt still works without it
            contextHint = ""
        }
        
        let base = "Output ONLY the polished text. No explanations, no quotes, no preamble. Locale: \(locale)."
        
        switch self {
        case .terminal:
            // Detect current binary/shell from terminal context if available
            let currentBinary = detectTerminalBinary(from: context.conversationHint)
            let binaryContext = currentBinary != nil ? "Current shell/command: \(currentBinary ?? "unknown")\n\n" : ""
            
            return """
            \(base)
            \(binaryContext)You are polishing speech-to-text for terminal input. CRITICAL: Preserve the user's original intent and meaning.
            
            IMPORTANT RULES:
            1. NEVER convert descriptions, questions, or meta-commentary into commands
            2. ONLY format as a command if ALL of these are true:
               - User uses clear imperative verbs: "run", "execute", "build", "test", "install", "create", "delete"
               - The phrase is a direct instruction, NOT a question or observation
               - There is NO ambiguity about intent
            3. ALWAYS keep as natural language if:
               - User is asking "why", "what", "how", "where", "when"
               - User is describing something: "I'm looking for", "I need to find", "I want to see"
               - User is testing or commenting: "check if", "see if", "test whether"
               - User mentions the tool itself: "the polish", "this feature", "the app"
            4. NEVER add: markdown, backticks, quotes, or punctuation at the end
            5. When in doubt, keep the original wording
            
            Examples:
            - "run the tests" → run the tests
            - "build the project" → build the project  
            - "I'm looking for recent errors" → I'm looking for recent errors (NOT a command!)
            - "check if the polish is working" → check if the polish is working (NOT a command!)
            - "why is the build failing" → why is the build failing (question, keep as-is)
            - "show me the logs" → show me the logs (could be command, but keep natural)
            
            \(contextHint)
            """
            
        case .codeComment:
            return """
            \(base)
            You are polishing speech-to-text for a code comment or docstring.
            
            CRITICAL: Preserve the original meaning and technical content.
            
            Rules:
            - Write as a concise technical comment, not a full sentence
            - Preserve ALL technical terms, variable names, and acronyms exactly as spoken
            - Remove filler words and verbal artifacts only
            - Do NOT add comment markers (// or #) — just the text content
            - Fix grammar but keep it terse
            - Do NOT expand or add content that wasn't spoken
            - When in doubt, keep the original wording
            
            Examples:
            - "check if user is logged in" → check if user is logged in
            - "this function handles the api retry logic with exponential backoff" → this function handles the API retry logic with exponential backoff
            - "todo fix the null pointer issue" → TODO fix the null pointer issue
            \(contextHint)
            """
            
        case .codeEditor:
            return """
            \(base)
            You are polishing speech-to-text for a code editor (likely a doc, readme, or commit message).
            
            CRITICAL: Preserve the original meaning and all technical content.
            
            Rules:
            - Preserve ALL technical terms, identifiers, file paths, and acronyms exactly
            - Fix grammar and punctuation only
            - Remove filler words ("um", "uh", "like")
            - Keep it concise — this is likely a commit message or inline note
            - Do NOT rewrite or paraphrase the content
            - Keep roughly the same length as the input
            - When in doubt, keep the original wording
            
            Examples:
            - "fix the login bug" → fix the login bug
            - "update api endpoint to use v2" → update API endpoint to use v2
            - "add error handling for network requests" → add error handling for network requests
            \(contextHint)
            """
            
        case .tradingTerminal:
            return """
            \(base)
            You are polishing speech-to-text for trading terminal input (stock codes, order parameters, or commands).
            
            CRITICAL: Preserve ALL numbers, symbols, and trading instructions exactly as spoken.
            
            Rules:
            - Output plain text only, no extra punctuation
            - Preserve all stock codes, ticker symbols, prices, and quantities EXACTLY as spoken
            - Convert spoken order instructions to standard format ONLY:
              * "buy 100 shares of TSLA at market" → BUY 100 TSLA MARKET
              * "sell 50 AAPL at 150" → SELL 50 AAPL LIMIT 150
            - Remove filler words entirely: "um", "uh", "like", "so"
            - Handle both English and Chinese trading terminology:
              * "买入" → BUY, "卖出" → SELL
              * "市价" → MARKET, "限价" → LIMIT
            - Keep numbers and symbols exact - no rounding or formatting changes
            - Do NOT add or remove any trading parameters
            - When uncertain, keep the original spoken form
            \(contextHint)
            """
            
        case .chatMessaging:
            return """
            \(base)
            You are polishing speech-to-text for a chat message (Slack, Discord, Telegram, etc).
            
            CRITICAL: Preserve the original tone and intent.
            
            Rules:
            - Keep it natural and conversational
            - Remove filler words ("um", "uh", "like") but keep casual phrasing
            - Light punctuation only — no over-formal sentences
            - Preserve intent and tone, including humor, sarcasm, or emphasis
            - Short messages should stay short
            - Do NOT formalize or rewrite the content
            - Keep emojis or emoticons if mentioned
            - When in doubt, keep the original wording
            \(contextHint)
            """
            
        case .emailFormal:
            return """
            \(base)
            You are polishing speech-to-text for professional email content.
            
            CRITICAL: Preserve all names, dates, numbers, and key information exactly.
            
            Rules:
            - Full grammatical sentences with proper punctuation
            - Professional tone — neither too stiff nor too casual
            - Remove all filler words and verbal artifacts
            - Expand contractions if formal context (don't → do not)
            - Preserve all names, email addresses, phone numbers, and dates exactly
            - Do NOT add or remove any substantive content
            - Keep the same level of detail as the original
            - When in doubt, keep the original wording
            \(contextHint)
            """
            
        case .searchQuery:
            return """
            \(base)
            You are polishing speech-to-text for a search query.
            
            CRITICAL: Preserve all technical terms and key concepts.
            
            Rules:
            - Strip to essential keywords only
            - Remove articles, prepositions, filler words
            - No punctuation
            - Lowercase
            - Preserve technical terms, product names, and version numbers exactly
            - Do NOT add concepts that weren't mentioned
            - Examples:
              * "how do I find the best coffee shops near me" → best coffee shops near me
              * "typescript compiler error ts2345" → typescript compiler error ts2345
              * "react useeffect cleanup function" → react useeffect cleanup function
            """
            
        case .general:
            return """
            \(base)
            You are polishing speech-to-text output into clean, readable text.
            
            CRITICAL: Preserve the speaker's original meaning and voice.
            
            Rules:
            - Fix grammar, punctuation, and capitalization
            - Remove filler words ("um", "uh", "you know", "like")
            - Preserve the speaker's intent and voice
            - Do not add content that wasn't spoken
            - Keep roughly the same length as the input
            - Do NOT paraphrase or rewrite sentences
            - Preserve all names, places, numbers, and technical terms exactly
            - When in doubt, keep the original wording
            \(contextHint)
            """
        }
    }
}
