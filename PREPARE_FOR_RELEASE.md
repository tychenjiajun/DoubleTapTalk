# DoubleTapTalk GitHub Release Preparation Guide

This document outlines all necessary steps before pushing DoubleTapTalk to GitHub for public distribution.

## ✅ Completed Items

- [x] Clean Git history with consistent author attribution
- [x] MIT License file added
- [x] Bilingual README (English + Chinese)
- [x] Comprehensive documentation in repository
- [x] Build scripts available (package-dmg.sh)
- [x] Debugging utilities included (view-logs.sh, check-polish-logs.sh)

## 🔧 Required Updates Before First Push

### 1. Update GitHub Actions Workflow

The current `.github/workflows/release.yml` references `DoubleTapTalk.xcodeproj` which no longer exists. Update it to use Swift Package Manager:

```yaml
name: Release
on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-14
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build with Swift PM
        run: |
          swift build -c release
          mkdir -p DoubleTapTalk.app/Contents/MacOS/
          cp .build/release/DoubleTapTalk DoubleTapTalk.app/Contents/MacOS/
          
      - name: Create DMG
        run: ./package-dmg.sh
        
      - name: Upload Release Asset
        uses: softprops/action-gh-release@v1
        with:
          files: DoubleTapTalk-*.dmg
```

### 2. Add Code Signing & Notarization (For Public Distribution)

To distribute outside Apple Developer account or through Mac App Store:

```bash
# 1. Create signing certificate in Xcode
# Keychain Access → Certificates → File Sharing Certificate

# 2. Sign the app
codesign --deep --force --verbose \
  --sign "Developer ID Application: Your Name" \
  DoubleTapTalk.app

# 3. Notarize via command line
xcrun notarytool submit DoubleTapTalk-1.0.0.dmg \
  --keychain-profile "notary-profile-name" \
  --wait

# 4. Staple ticket
xcrun stapler staple DoubleTapTalk-1.0.0.dmg
```

### 3. Update Version Numbering

Follow Semantic Versioning (SemVer): MAJOR.MINOR.PATCH

- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes

Current version: **1.0.0** ✅

### 4. Create CONTRIBUTING.md

Document how others can contribute:

```markdown
# Contributing to DoubleTapTalk

## How to Contribute
1. Fork the repository
2. Create feature branch
3. Make changes with tests
4. Submit pull request

## Coding Guidelines
- Follow existing Swift style
- Add logging for new features
- Update documentation
```

### 5. Check for Secrets in Code

Run this before pushing:
```bash
grep -r "api.key\|secret\|password\|token" Sources/ --exclude-dir=".git" || echo "✅ No exposed secrets"
```

### 6. Final .gitignore Check

Ensure these are ignored:
```
.build/
DoubleTapTalk.app/
*.dmg
.env
.env.local
secrets.plist
```

## 🚀 Pre-Launch Steps

### Day 1: Prepare Repository
- [ ] Update GitHub Actions workflow
- [ ] Add CONTRIBUTING.md
- [ ] Verify no secrets in codebase
- [ ] Test complete build process from scratch
- [ ] Update all URLs/placeholders

### Day 2: Initial Push
```bash
# Create new private repo on GitHub first
git remote add origin git@github.com:tychenjiajun/doubletap-talk.git
git push --force-with-lease origin master  # Force due to rewritten history

# Then make repository PUBLIC when ready
```

### Day 3: Create First Release
```bash
# Tag the release
git tag -a v1.0.0 -m "DoubleTapTalk 1.0.0 - Initial Release"
git push origin v1.0.0

# Or create draft release manually on GitHub
# Assets will auto-upload via Actions
```

## 📦 Alternative Distribution Methods

### Option A: GitHub Releases (Recommended)
- Free hosting
- Built-in versioning
- Easy updates for users
- Download statistics

### Option B: Personal Website
- More control over presentation
- Can add custom download analytics
- Requires hosting setup

### Option C: Mac App Store
- Revenue potential
- Automatic updates built-in
- Strict review process
- 30% Apple commission

## 🔒 Security Considerations

### API Keys
- ✅ Never commit API keys
- ✅ Use environment variables
- ✅ Document key requirements in README
- ✅ Provide placeholder examples

### User Data
- ✅ All data stored locally
- ✅ No telemetry/analytics
- ✅ Privacy policy documented

### Network Security
- ✅ HTTPS-only connections
- ✅ Certificate pinning considered
- ✅ API key encryption (macOS Keychain)

## 📊 Post-Launch Monitoring

1. **GitHub Issues**: Respond within 48 hours
2. **Stars/Forks**: Track adoption
3. **Downloads**: Monitor release page stats
4. **Bug Reports**: Prioritize and fix quickly

---

## Quick Reference Commands

```bash
# Build release
swift build -c release

# Create DMG
./package-dmg.sh

# Sign locally (development)
codesign --force --deep --sign "-" DoubleTapTalk.app

# Notarize (requires developer account)
xcrun notarytool submit DoubleTapTalk-1.0.0.dmg --apple-id your@email.com --team-id YOURTEAMID --password password --wait

# Create annotated tag
git tag -a v1.0.1 -m "Bug fixes and improvements"
git push origin v1.0.1

# Force push after history rewrite
git push --force-with-lease origin master
```

---

Last Updated: 2024-04-06  
Author: Jiajun Chen <tychenjiajun@live.cn>
