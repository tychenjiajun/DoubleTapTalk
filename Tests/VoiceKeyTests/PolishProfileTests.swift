import XCTest
@testable import DoubleTapTalk

/// Unit tests for PolishProfile detection logic
final class PolishProfileTests: XCTestCase {
    
    // MARK: - Terminal Detection Tests
    
    func testDetectTerminalApp() {
        let terminalContexts: [(String, String?)] = [
            ("Terminal", "com.apple.Terminal"),
            ("iTerm2", "com.googlecode.iterm2"),
            ("Warp", "dev.warp.Warp-Stable"),
            ("Hyper", "co.zeit.hyper"),
        ]
        
        for (appName, bundleID) in terminalContexts {
            let context = createMockContext(appName: appName, bundleID: bundleID, isTerminal: true)
            let profile = PolishProfile.detect(from: context)
            XCTAssertEqual(profile, .terminal, "Should detect terminal profile for \(appName)")
        }
    }
    
    // MARK: - Code Editor Detection Tests
    
    func testDetectCodeEditorInNormalArea() {
        let context = createMockContext(
            appName: "VSCode",
            bundleID: "com.microsoft.VSCode",
            isCodeEditor: true,
            focusedElementRole: "AXTextField"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .codeEditor, "Should detect code editor profile for normal text field")
    }
    
    func testDetectCodeCommentInTextArea() {
        let context = createMockContext(
            appName: "VSCode",
            bundleID: "com.microsoft.VSCode",
            isCodeEditor: true,
            focusedElementRole: "AXTextArea"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .codeComment, "Should detect code comment profile for text area")
    }
    
    func testDetectCodeCommentInReviewWindow() {
        let context = createMockContext(
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            isCodeEditor: true,
            focusedElementRole: "AXTextField",
            windowTitle: "Code Review"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .codeComment, "Should detect code comment profile in review window")
    }
    
    // MARK: - Browser/Search Query Detection Tests
    
    func testDetectSearchQueryInBrowserTextField() {
        let context = createMockContext(
            appName: "Chrome",
            bundleID: "com.google.Chrome",
            isBrowser: true,
            focusedElementRole: "AXTextField"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .searchQuery, "Should detect search query profile in browser text field")
    }
    
    func testDetectGeneralInBrowserTextArea() {
        let context = createMockContext(
            appName: "Chrome",
            bundleID: "com.google.Chrome",
            isBrowser: true,
            focusedElementRole: "AXTextArea"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .general, "Should detect general profile in browser text area")
    }
    
    // MARK: - Chat/Messaging Detection Tests
    
    func testDetectChatMessagingApps() {
        let chatApps: [(String, String)] = [
            ("Slack", "com.tinyspeck.slackmacgap"),
            ("Discord", "com.hnc.Discord"),
            ("Telegram", "ru.keepcoder.Telegram"),
            ("WeChat", "com.tencent.xinWeChat"),
            ("QQ", "com.tencent.qq"),
            ("DingTalk", "com.laiwang.DingTalk"),
            ("LINE", "jp.naver.line.mac"),
            ("Teams", "com.microsoft.teams2"),
            ("WhatsApp", "net.whatsapp.WhatsApp"),
        ]
        
        for (appName, bundleID) in chatApps {
            let context = createMockContext(appName: appName, bundleID: bundleID)
            let profile = PolishProfile.detect(from: context)
            XCTAssertEqual(profile, .chatMessaging, "Should detect chat messaging profile for \(appName)")
        }
    }
    
    // MARK: - Email Detection Tests
    
    func testDetectEmailFormalApps() {
        let emailApps: [(String, String)] = [
            ("Mail", "com.apple.mail"),
            ("Outlook", "com.microsoft.Outlook"),
            ("Thunderbird", "org.mozilla.thunderbird"),
        ]
        
        for (appName, bundleID) in emailApps {
            let context = createMockContext(appName: appName, bundleID: bundleID)
            let profile = PolishProfile.detect(from: context)
            XCTAssertEqual(profile, .emailFormal, "Should detect email formal profile for \(appName)")
        }
    }
    
    func testDetectGmailInBrowser() {
        let context = createMockContext(
            appName: "Chrome",
            bundleID: "com.google.Chrome",
            isBrowser: true,
            windowTitle: "Gmail - Compose"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .emailFormal, "Should detect email formal profile for Gmail in browser")
    }
    
    // MARK: - Trading Terminal Detection Tests
    
    func testDetectTradingApps() {
        let tradingApps: [(String, String)] = [
            ("同花顺", "cn.com.10jqka.macstockPro"),
            ("大智慧", "cn.com.gw.DZH"),
            ("富途牛牛", "cn.futu.Niuniu"),
            ("东方财富", "com.emmac.mac"),
            ("Schwab", "com.schwab.SchwabMobile"),
            ("E*TRADE", "com.etrade.mobile.pro"),
            ("IBKR TWS", "com.interactivebrokers.TWS"),
        ]
        
        for (appName, bundleID) in tradingApps {
            let context = createMockContext(
                appName: appName,
                bundleID: bundleID,
                isTradingApp: true
            )
            let profile = PolishProfile.detect(from: context)
            XCTAssertEqual(profile, .tradingTerminal, "Should detect trading terminal profile for \(appName)")
        }
    }
    
    // MARK: - Note-Taking Apps Detection Tests
    
    func testDetectNoteAppsAsGeneral() {
        let noteApps: [(String, String)] = [
            ("Notion", "notion.id"),
            ("Obsidian", "md.obsidian"),
            ("OneNote", "com.microsoft.onenote.mac"),
            ("Evernote", "com.evernote.Evernote"),
            ("Bear", "net.shinyfrog.bear"),
            ("Linear", "com.linear"),
            ("Todoist", "com.todoist.mac.Todoist"),
        ]
        
        for (appName, bundleID) in noteApps {
            let context = createMockContext(appName: appName, bundleID: bundleID)
            let profile = PolishProfile.detect(from: context)
            XCTAssertEqual(profile, .general, "Should detect general profile for \(appName)")
        }
    }
    
    // MARK: - Fallback Tests
    
    func testDetectGeneralForUnknownApp() {
        let context = createMockContext(
            appName: "UnknownApp",
            bundleID: "com.unknown.app"
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .general, "Should fallback to general profile for unknown apps")
    }
    
    func testDetectGeneralForNilBundleID() {
        let context = createMockContext(
            appName: "UnknownApp",
            bundleID: nil
        )
        let profile = PolishProfile.detect(from: context)
        XCTAssertEqual(profile, .general, "Should fallback to general profile for nil bundle ID")
    }
    
    // MARK: - System Prompt Tests
    
    func testTerminalSystemPrompt() {
        let context = createPolishContext(profile: .terminal)
        let prompt = PolishProfile.terminal.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("terminal input"), "Terminal prompt should mention terminal input")
        XCTAssertTrue(prompt.contains("Terminal:"), "Terminal prompt should mention command formatting rules")
        XCTAssertTrue(prompt.contains("no backticks or markdown"), "Terminal prompt should forbid markdown")
        XCTAssertTrue(prompt.contains("Output ONLY"), "All prompts should require output-only response")
    }
    
    func testCodeCommentSystemPrompt() {
        let context = createPolishContext(profile: .codeComment)
        let prompt = PolishProfile.codeComment.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("code comment"), "Code comment prompt should mention comments")
        XCTAssertTrue(prompt.contains("no // or # markers"), "Should instruct not to add markers")
        XCTAssertTrue(prompt.contains("concise"), "Should emphasize conciseness")
    }
    
    func testChatMessagingSystemPrompt() {
        let context = createPolishContext(profile: .chatMessaging)
        let prompt = PolishProfile.chatMessaging.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("conversational"), "Chat prompt should mention conversational tone")
        XCTAssertTrue(prompt.contains("conversational and natural"), "Should keep messages natural")
        XCTAssertTrue(prompt.contains("emojis"), "Should preserve emojis")
    }
    
    func testEmailFormalSystemPrompt() {
        let context = createPolishContext(profile: .emailFormal)
        let prompt = PolishProfile.emailFormal.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("professional"), "Email prompt should mention professional tone")
        XCTAssertTrue(prompt.contains("proper punctuation"), "Should require proper punctuation")
        XCTAssertTrue(prompt.contains("expand contractions"), "Should mention expanding contractions")
    }
    
    func testTradingTerminalSystemPrompt() {
        let context = createPolishContext(profile: .tradingTerminal)
        let prompt = PolishProfile.tradingTerminal.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("BUY"), "Trading prompt should mention BUY format")
        XCTAssertTrue(prompt.contains("SELL"), "Trading prompt should mention SELL format")
        XCTAssertTrue(prompt.contains("MARKET"), "Trading prompt should mention MARKET orders")
        XCTAssertTrue(prompt.contains("LIMIT"), "Trading prompt should mention LIMIT orders")
        XCTAssertTrue(prompt.contains("买入"), "Trading prompt should handle Chinese buy term")
        XCTAssertTrue(prompt.contains("卖出"), "Trading prompt should handle Chinese sell term")
    }
    
    func testSearchQuerySystemPrompt() {
        let context = createPolishContext(profile: .searchQuery)
        let prompt = PolishProfile.searchQuery.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("keywords"), "Search prompt should mention keywords")
        XCTAssertTrue(prompt.contains("no trailing punctuation"), "Should require no trailing punctuation")
        XCTAssertTrue(prompt.contains("essential keywords"), "Should strip to essential keywords")
    }
    
    func testGeneralSystemPrompt() {
        let context = createPolishContext(profile: .general)
        let prompt = PolishProfile.general.systemPrompt(context: context)
        
        XCTAssertTrue(prompt.contains("grammar"), "General prompt should mention grammar")
        XCTAssertTrue(prompt.contains("filler words"), "Should mention removing filler words")
        XCTAssertTrue(prompt.contains("intent"), "Should preserve speaker intent")
    }
    
    // MARK: - Bundle ID Mappings Tests
    
    func testBundleIDMappingsContainCategories() {
        XCTAssertFalse(BundleIDMappings.all.isEmpty, "Bundle ID mappings should not be empty")
        
        // Check key categories exist
        XCTAssertTrue(BundleIDMappings.all["visual-studio-code"] != nil, "Should have VSCode mappings")
        XCTAssertTrue(BundleIDMappings.all["slack"] != nil, "Should have Slack mappings")
        XCTAssertTrue(BundleIDMappings.all["google-chrome"] != nil, "Should have Chrome mappings")
        XCTAssertTrue(BundleIDMappings.all["terminal"] != nil, "Should have Terminal mappings")
        XCTAssertTrue(BundleIDMappings.all["tonghuashun"] != nil, "Should have Chinese trading app mappings")
    }
    
    func testBundleIDMappingsGetAll() {
        let allBundleIDs = BundleIDMappings.getAll()
        XCTAssertGreaterThan(allBundleIDs.count, 50, "Should have at least 50 unique bundle IDs")
        
        // Check some specific bundle IDs exist
        XCTAssertTrue(allBundleIDs.contains("com.microsoft.VSCode"), "Should include VSCode")
        XCTAssertTrue(allBundleIDs.contains("com.apple.Safari"), "Should include Safari")
        XCTAssertTrue(allBundleIDs.contains("com.tinyspeck.slackmacgap"), "Should include Slack")
    }
    
    func testBundleIDMappingsContains() {
        XCTAssertTrue(BundleIDMappings.contains(bundleID: "com.microsoft.VSCode", category: "visual-studio-code"))
        XCTAssertTrue(BundleIDMappings.contains(bundleID: "com.google.Chrome", category: "google-chrome"))
        XCTAssertTrue(BundleIDMappings.contains(bundleID: "com.apple.Terminal", category: "terminal"))
        
        XCTAssertFalse(BundleIDMappings.contains(bundleID: "com.apple.Safari", category: "terminal"))
        XCTAssertFalse(BundleIDMappings.contains(bundleID: "unknown.bundle", category: "slack"))
    }
    
    // MARK: - Helper Methods
    
    private func createMockContext(
        appName: String = "TestApp",
        bundleID: String? = "com.test.app",
        isTerminal: Bool = false,
        isBrowser: Bool = false,
        isCodeEditor: Bool = false,
        isTradingApp: Bool = false,
        focusedElementRole: String? = nil,
        windowTitle: String? = nil
    ) -> AppContext {
        return AppContext(
            appName: appName,
            bundleID: bundleID,
            isTerminal: isTerminal,
            isBrowser: isBrowser,
            isCodeEditor: isCodeEditor,
            isTradingApp: isTradingApp,
            focusedElementRole: focusedElementRole,
            windowTitle: windowTitle,
            focusedElementValue: nil
        )
    }
    
    private func createPolishContext(profile: PolishProfile) -> PolishContext {
        let appContext = createMockContext()
        return PolishContext(
            targetApp: appContext,
            existingText: "Test existing text",
            conversationHint: "Test conversation hint",
            userLocale: "en_US"
        )
    }
}
