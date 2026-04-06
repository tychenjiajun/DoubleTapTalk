#!/bin/bash
# VoiceKey Log Viewer Script

LOG_FILE="$HOME/Library/Caches/VoiceKey.log"

echo "=== VoiceKey Log Viewer ==="
echo "Log file: $LOG_FILE"
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found. Make sure VoiceKey app has been run."
    exit 1
fi

# Show last 50 lines by default, or use argument for custom count
LINES=${1:-50}

echo "=== Last $LINES lines ==="
tail -n "$LINES" "$LOG_FILE"

echo ""
echo "=== Options ==="
echo "  ./view-logs.sh          - Show last 50 lines"
echo "  ./view-logs.sh 100      - Show last 100 lines"
echo "  ./view-logs.sh all      - Show all logs"
echo "  ./view-logs.sh clear    - Clear log file"
echo "  ./view-logs.sh watch    - Follow log in real-time"

# Handle commands
case "$1" in
    all)
        cat "$LOG_FILE"
        ;;
    clear)
        > "$LOG_FILE"
        echo "Log file cleared."
        ;;
    watch)
        echo "Following logs (Ctrl+C to stop)..."
        tail -f "$LOG_FILE"
        ;;
esac
