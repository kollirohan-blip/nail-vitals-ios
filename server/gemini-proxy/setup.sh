#!/bin/bash
# One-time setup for the app's Q&A assistant server. Run it yourself in
# Terminal (it opens a browser to sign in and asks for your Gemini key):
#
#   bash ~/Documents/nail-vitals-ios/server/gemini-proxy/setup.sh
#
# Needs a free Cloudflare account and a Gemini API key from Google AI
# Studio. The key goes straight into Cloudflare as a secret; it is never
# written to this repo or into the app. Safe to run again (e.g. to redeploy
# after editing src/worker.js); it keeps the existing app token.
set -euo pipefail
cd "$(dirname "$0")"

# Wrangler asks questions (a workers.dev name, your key), which only works
# in a real terminal window.
if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "Please run this in a Terminal window (not a command box), so it can ask you questions:"
  echo "  bash ~/Documents/nail-vitals-ios/server/gemini-proxy/setup.sh"
  exit 1
fi

CONFIG="../../nail-vitals-ios/NailVitals/NailVitals/NailVitals/AssistantConfig.plist"
wrangler() { npx --yes wrangler "$@"; }

echo
echo "== 1/5  Cloudflare sign-in"
if ! wrangler whoami 2>/dev/null | grep -qi "associated with the email"; then
  wrangler login
fi

echo
echo "== 2/5  Deploying the server"
echo "(The first time, Cloudflare asks you to pick a workers.dev name: answer yes and pick any name.)"
LOG=$(mktemp)
# `script` records the output while keeping the terminal interactive, so
# wrangler can still ask its questions.
script -q "$LOG" npx --yes wrangler deploy
URL=$(grep -Eo 'https://[A-Za-z0-9.-]+\.workers\.dev' "$LOG" | head -1 || true)
rm -f "$LOG"
if [ -z "$URL" ]; then
  read -r -p "Paste the https://...workers.dev address printed above: " URL
fi

echo
echo "== 3/5  Gemini API key"
if [ "${1:-}" = "--new-key" ] || ! wrangler secret list 2>/dev/null | grep -q GEMINI_API_KEY; then
  echo "Paste your Gemini API key and press Return (input stays hidden)."
  wrangler secret put GEMINI_API_KEY
else
  echo "Already set. (Run with --new-key to replace it.)"
fi

echo
echo "== 4/5  App token"
TOKEN=""
if [ -f "$CONFIG" ]; then
  TOKEN=$(/usr/libexec/PlistBuddy -c "Print :AppToken" "$CONFIG" 2>/dev/null || true)
fi
if [ -z "$TOKEN" ]; then
  TOKEN=$(openssl rand -hex 24)
fi
printf '%s' "$TOKEN" | wrangler secret put APP_TOKEN >/dev/null
cat > "$CONFIG" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Endpoint</key>
	<string>$URL</string>
	<key>AppToken</key>
	<string>$TOKEN</string>
</dict>
</plist>
PLIST
echo "Saved the server address for the app (AssistantConfig.plist, ignored by git)."

echo
echo "== 5/5  Test"
sleep 3
echo "Models this key can use:"
curl -s -H "x-app-token: $TOKEN" "$URL/models"
echo
echo
echo "Test question: What is finger clubbing?"
curl -s -X POST "$URL/ask" -H "content-type: application/json" -H "x-app-token: $TOKEN" \
  -d '{"question":"What is finger clubbing?","context":"","history":[]}'
echo
echo
echo "Done. Rebuild the app in Xcode and try 'Ask about this result'."
