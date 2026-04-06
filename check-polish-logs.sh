#!/bin/bash
echo "🔍 VoiceKey Polishing Debug Tool"
echo "================================="
echo ""
echo "Latest polishing attempt:"
tail -80 ~/Library/Caches/VoiceKey.log | grep -B 5 -A 15 "Applying LLM polishing"

echo ""
echo "Enhanced JSON parser output (if available):"
tail -80 ~/Library/Caches/VoiceKey.log | grep -E "Full OpenAI|Parsed using|Unknown response|Available keys"

echo ""
echo "Most recent error (if any):"
tail -20 ~/Library/Caches/VoiceKey.log | grep "ERROR" | tail -1
