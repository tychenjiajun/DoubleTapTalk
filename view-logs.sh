#!/bin/bash
# VoiceKey Log Viewer Script - Enhanced with Status Checking

LOG_FILE="$HOME/Library/Caches/VoiceKey.log"

show_status() {
    echo "=== VoiceKey Status Check ==="
    echo ""
    
    # Check if app is running
    if pgrep -x "VoiceKey" > /dev/null; then
        echo "✓ VoiceKey is RUNNING"
    else
        echo "✗ VoiceKey is NOT running"
    fi
    
    # Check accessibility permissions
    result=$(osascript -e 'tell application "System Events" to get (name of processes where enabled is true)' 2>/dev/null | grep -i voicekey)
    if [ -n "$result" ]; then
        echo "✓ Accessibility permission GRANTED"
    else
        echo "⚠ Accessibility permission NOT granted"
        echo ""
        echo "To fix hotkey issues:"
        echo "1. Open System Settings → Privacy & Security → Accessibility"
        echo "2. Click lock icon and enter password"
        echo "3. Add VoiceKey from /Applications folder"
        echo "4. Restart VoiceKey"
    fi
    
    # Check log file
    if [ -f "$LOG_FILE" ]; then
        error_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$error_count" -gt 0 ]; then
            echo "⚠ Found $error_count ERROR(s) in log"
        fi
        
        # Check for specific known issues
        if grep -q "Failed to create event tap" "$LOG_FILE"; then
            echo ""
            echo "⚠ HOTKEY ISSUE DETECTED!"
            echo "   Hotkeys require accessibility permission."
            echo "   Run: ./view-logs.sh status"
        fi
    fi
}

echo "=== VoiceKey Log Viewer ==="
echo "Log file: $LOG_FILE"
echo ""

case "${1:-tail}" in
    status|check)
        show_status
        ;;
    watch|follow|-f)
        if [ ! -f "$LOG_FILE" ]; then
            echo "Log file not found. Start VoiceKey first."
            exit 1
        fi
        echo "Following logs (Ctrl+C to stop)..."
        tail -f "$LOG_FILE"
        ;;
    clear)
        if [ -f "$LOG_FILE" ]; then
            rm "$LOG_FILE"
            echo "Log file cleared."
        else
            echo "Log file does not exist."
        fi
        ;;
    all)
        cat "$LOG_FILE"
        ;;
    tail)
        if [ ! -f "$LOG_FILE" ]; then
            echo "Log file not found. Start VoiceKey first."
            exit 1
        fi
        tail -100 "$LOG_FILE"
        ;;
    *)
        # Default: show last N lines or check status
        LINES=${1:-50}
        if [ ! -f "$LOG_FILE" ]; then
            echo "Log file not found. Make sure VoiceKey app has been run."
            echo ""
            show_status
            exit 1
        fi
        echo "=== Last $LINES lines ==="
        tail -n "$LINES" "$LOG_FILE"
        ;;
esac

echo ""
echo "=== Quick Commands ==="
echo "  ./view-logs.sh          - Show last 50 lines"
echo "  ./view-logs.sh 100      - Show last 100 lines"
echo "  ./view-logs.sh all      - Show all logs"
echo "  ./view-logs.sh clear    - Clear log file"
echo "  ./view-logs.sh watch    - Follow log in real-time"
echo "  ./view-logs.sh status   - Check app and permissions status"
