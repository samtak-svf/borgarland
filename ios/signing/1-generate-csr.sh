#!/usr/bin/env bash
# Step 1 of iOS signing setup: generate a certificate signing request and the
# private key that goes with it.
#
# Runs on Linux. No Mac is involved in any step of this directory, and that is
# the point: the chain openssl -> Apple's web UI -> GitHub Actions has already
# produced a real signed TestFlight build for another app on this same team
# (issue #37), so nothing here is theoretical.
#
# After this script runs:
#   1. Upload ios-signing.csr to
#      https://developer.apple.com/account/resources/certificates/add
#      -> Software -> "Apple Distribution" -> Continue -> upload -> download the .cer
#   2. Run ./2-convert-cert.sh <path-to-downloaded.cer>
#
# KEEP ios-signing.key SECRET. It cannot be recovered; losing it means
# re-issuing the certificate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$SCRIPT_DIR/.secrets"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [[ -f "$SECRETS_DIR/ios-signing.key" ]]; then
  echo "ERROR: $SECRETS_DIR/ios-signing.key already exists."
  echo "Delete it first if you really want to regenerate."
  exit 1
fi

# Apple ignores the subject and issues against the team, so these fields are
# descriptive only. The organisation named is the TEAM's legal entity, which is
# the party rather than Samtak svf.: the app ships through the party's Apple
# team for the field test because that team exists and works today, a decision
# taken deliberately and reversibly in issue #37. ASCII throughout, because the
# entity-class fields reject Icelandic characters.
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$SECRETS_DIR/ios-signing.key" \
  -out "$SECRETS_DIR/ios-signing.csr" \
  -subj "/CN=Borgarland iOS Distribution/O=Sosialistaflokkur Islands/C=IS/emailAddress=gudrodur@gmail.com"

chmod 600 "$SECRETS_DIR/ios-signing.key"

echo ""
echo "Generated:"
echo "  Private key: $SECRETS_DIR/ios-signing.key"
echo "  CSR:         $SECRETS_DIR/ios-signing.csr"
echo ""
echo "Next steps:"
echo "  1. Go to https://developer.apple.com/account/resources/certificates/add"
echo "  2. Select 'Apple Distribution' under Software"
echo "  3. Click Continue, upload $SECRETS_DIR/ios-signing.csr"
echo "  4. Download the resulting .cer file"
echo "  5. Run: ./2-convert-cert.sh /path/to/downloaded.cer"
