#!/usr/bin/env bash
# Step 2 of iOS signing setup: turn Apple's .cer into a .p12 bundle that carries
# the private key alongside the signed certificate. The .p12 is what GitHub
# Actions imports; Apple never sees the key.
#
# Prerequisites: ./1-generate-csr.sh has run, and the .cer has been downloaded
# from https://developer.apple.com/account/resources/certificates/
#
# After this script runs:
#   1. Encode for GitHub Secrets:  base64 -w0 .secrets/ios-signing.p12
#   2. Add both values under Settings -> Secrets and variables -> Actions:
#        IOS_SIGNING_P12_BASE64   <- the base64 string
#        IOS_SIGNING_P12_PASSWORD <- the password printed below

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$SCRIPT_DIR/.secrets"
KEY_FILE="$SECRETS_DIR/ios-signing.key"

CER_PATH="${1:-}"
if [[ -z "$CER_PATH" ]]; then
  echo "Usage: $0 <path-to-downloaded.cer> [p12-password]"
  echo ""
  echo "  p12-password: optional. If omitted, a random 32-char password is generated"
  echo "                and printed. Save it, GitHub Secrets needs it."
  exit 1
fi

if [[ ! -f "$CER_PATH" ]]; then
  echo "ERROR: $CER_PATH not found"
  exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "ERROR: $KEY_FILE not found. Run ./1-generate-csr.sh first."
  exit 1
fi

PASSWORD="${2:-$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)}"

# Apple hands out a DER-encoded .cer; openssl pkcs12 wants PEM.
openssl x509 -in "$CER_PATH" -inform DER -out "$SECRETS_DIR/ios-distribution.pem" -outform PEM

# -legacy is required: the modern default uses AES-256 for the certificate bag,
# and macOS's security(1) on the runner cannot import that.
openssl pkcs12 -export \
  -inkey "$KEY_FILE" \
  -in "$SECRETS_DIR/ios-distribution.pem" \
  -out "$SECRETS_DIR/ios-signing.p12" \
  -password "pass:$PASSWORD" \
  -legacy

chmod 600 "$SECRETS_DIR/ios-signing.p12"

echo ""
echo "Created: $SECRETS_DIR/ios-signing.p12"
echo ""
echo "Password:"
echo "  $PASSWORD"
echo ""
echo "Base64-encode for GitHub Secrets:"
echo "  base64 -w0 $SECRETS_DIR/ios-signing.p12"
echo ""
echo "Add these two at https://github.com/samtak-svf/borgarland/settings/secrets/actions:"
echo "  IOS_SIGNING_P12_BASE64   <- (output of the base64 command above)"
echo "  IOS_SIGNING_P12_PASSWORD <- $PASSWORD"
