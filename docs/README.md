# DoubleTapTalk Documentation

This directory contains technical documentation for DoubleTapTalk developers and contributors.

## Available Documents

### For Users
- **[README.md](../README.md)** - Main documentation with installation, features, and usage guide
- **[README_zh-CN.md](../README_zh-CN.md)** - Chinese version of the main documentation
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - Guide for contributing to the project

### For Developers
- **[PROMPT_FIXES.md](PROMPT_FIXES.md)** - Technical details on LLM prompt engineering fixes and hallucination prevention
- **[RFC-001-abandon-segment.md](RFC-001-abandon-segment.md)** - RFC: spoken abandon (dropping a relay segment on request) using the decision model
- **[RFC-002-polish-decision.md](RFC-002-polish-decision.md)** - RFC: decision model for polishing (gate, routing, verification) — deferred, with the evidence
- **[JEV_INTEGRATION.md](JEV_INTEGRATION.md)** - How to apply the Bocha Jev decision model: API contract, pipeline placement, logging, secrets, eval harness

## Project Structure

```
voice-key/
├── README.md                 # Main English documentation
├── README_zh-CN.md          # Main Chinese documentation
├── CONTRIBUTING.md          # Contribution guidelines
├── docs/                    # Technical documentation (this directory)
│   ├── README.md           # This file - documentation index
│   ├── PROMPT_FIXES.md     # LLM prompt engineering details
│   ├── JEV_INTEGRATION.md  # Decision-model integration guide
│   ├── RFC-001-abandon-segment.md   # Spoken abandon RFC
│   └── RFC-002-polish-decision.md   # Polish decision RFC (deferred)
├── Sources/                 # Application source code
├── Tests/                   # Unit tests
└── Scripts/                 # Helper scripts
```

## Quick Links

- **GitHub Repository**: https://github.com/tychenjiajun/voice-key
- **Issue Tracker**: https://github.com/tychenjiajun/voice-key/issues
- **Log File Location**: `~/Library/Caches/DoubleTapTalk.log`

## Need Help?

1. Check the [README.md](../README.md) for common issues and troubleshooting
2. Review [CONTRIBUTING.md](../CONTRIBUTING.md) for development guidelines
3. Open an issue on GitHub for bugs or feature requests

---

**Last Updated**: 2026-10-03
