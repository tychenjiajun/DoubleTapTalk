#!/bin/bash
# Creates (once) a stable self-signed code-signing identity named
# "DoubleTapTalk Local Signing" in the login keychain.
#
# Why: with ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) the app's Designated
# Requirement is `cdhash H"..."`. Every rebuild produces a new cdhash, so macOS
# TCC stops matching the stored Accessibility/Microphone grant — the toggles in
# System Settings stay ON while tccd logs
#   "Failed to match existing code requirement for subject com.jiajun.doubletaptalk".
# A certificate-backed identity gives a stable DR
#   identifier "com.jiajun.doubletaptalk" and certificate root = H"<cert>"
# so you grant the permission once and it survives rebuilds.
set -euo pipefail

IDENT_NAME="DoubleTapTalk Local Signing"
SIGN_DIR="$HOME/.doubletaptalk-signing"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENT_NAME"; then
    echo "✓ Signing identity already present: $IDENT_NAME"
    exit 0
fi

echo "=== Creating code-signing identity: $IDENT_NAME ==="
mkdir -p "$SIGN_DIR"
cd "$SIGN_DIR"

cat > openssl.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = DoubleTapTalk Local Signing
O = DoubleTapTalk
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout key.pem -out cert.pem -config openssl.cnf >/dev/null 2>&1

if ! openssl pkcs12 -export -legacy -out identity.p12 \
        -inkey key.pem -in cert.pem -passout pass:dt >/dev/null 2>&1; then
    openssl pkcs12 -export -out identity.p12 \
        -inkey key.pem -in cert.pem -passout pass:dt >/dev/null 2>&1
fi

security import identity.p12 -k "$KC" -P dt \
    -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null

if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KC" cert.pem 2>/dev/null; then
    echo "⚠ Could not set trust automatically. Open Keychain Access →"
    echo "  login → Certificates → \"$IDENT_NAME\" → Get Info → Trust →"
    echo "  Always Trust, then re-run this script."
    exit 1
fi

echo "✓ Identity ready:"
security find-identity -v -p codesigning | grep "$IDENT_NAME"
