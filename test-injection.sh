#!/bin/bash

echo "=== VoiceKey Injection Method Tester ==="
echo ""
echo "This script helps you verify which injection method is working:"
echo ""
echo "Method 1: Browser Test"
echo "  1. Open Chrome/Safari and click into any text field"
echo "  2. Run: ./test-injection.sh browser"
echo "  3. Click VoiceKey menu → Start Recording"
echo "  4. Speak, then Stop Recording"
echo "  5. Check logs: ./view-logs.sh tail | grep -i 'browser\\|pasteboard'"
echo ""
echo "Method 2: Native App Test"
echo "  1. Open Terminal or TextEdit"
echo "  2. Run: ./test-injection.sh native"
echo "  3. Record and stop"
echo "  4. Check logs: ./view-logs.sh tail | grep -i 'direct\\|injection'"
echo ""
echo "Manual verification:"
echo "  $ ./view-logs.sh watch    # Real-time monitoring"
echo "  $ ./view-logs.sh tail     # Last 100 lines"

case "$1" in
    browser)
        echo ""
        echo "Testing BROWSER injection..."
        open "https://www.google.com"
        echo "Opened Google. Focus the search box, then record!"
        sleep 2
        tail -n 20 ~/Library/Caches/VoiceKey.log | grep -E "browser|pasteboard|injection" || echo "No logs yet - start recording first"
        ;;
    native)
        echo ""
        echo "Testing NATIVE app injection..."
        open -a Terminal
        echo "Open Terminal, focus a window, then record!"
        sleep 2
        tail -n 20 ~/Library/Caches/VoiceKey.log | grep -E "direct|injection" || echo "No logs yet - start recording first"
        ;;
    *)
        echo "$0"
        ;;
esac
