#!/usr/bin/env bash
# Fetch the Android upload key from Secret Manager and write the two files a
# local signed build needs. CI does not use this -- it reads the same material
# from GitHub secrets (.github/workflows/android-release.yml).
#
# The key cannot be rotated once Play pins the upload certificate to
# is.borgarland, so it lives in exactly two places on purpose: Secret Manager
# and the GitHub secret. Everything this script writes is gitignored, and this
# repository is public.
set -euo pipefail

PROJECT=fedora-setup-secrets
ACCOUNT=gudrodur@gmail.com
DEST_DIR="$(cd "$(dirname "$0")/.." && pwd)/android/app"
KEYSTORE="$DEST_DIR/borgarland-upload.p12"
PROPS="$DEST_DIR/keystore.properties"

current="$(gcloud config get-value account 2>/dev/null || true)"
if [[ "$current" != "$ACCOUNT" ]]; then
  echo "gcloud is on '${current:-none}', this needs $ACCOUNT" >&2
  echo "  gcloud config set account $ACCOUNT" >&2
  exit 1
fi

read_secret () {
  gcloud secrets versions access latest --secret="$1" --project="$PROJECT"
}

# Read everything before writing anything, so a failed fetch cannot leave a
# half-written keystore that signs nothing and reports no error until CI.
b64="$(read_secret borgarland-android-upload-keystore)"
pw="$(read_secret borgarland-android-upload-keystore-password)"
alias_name="$(read_secret borgarland-android-upload-key-alias)"

umask 077
printf '%s' "$b64" | base64 -d > "$KEYSTORE"
cat > "$PROPS" <<EOF
storeFile=$(basename "$KEYSTORE")
storePassword=$pw
keyAlias=$alias_name
keyPassword=$pw
EOF

# Prove the key is the one Play will accept, rather than assuming the fetch
# worked. This is the same fingerprint the release workflow pins.
EXPECTED=35F297E41BE8BB04E3362130C926D57A860CDCF9D0A1108B0E9C33DE1F03184C
actual="$(keytool -list -v -keystore "$KEYSTORE" -storepass "$pw" 2>/dev/null \
  | grep -m1 'SHA256:' | awk '{print $2}' | tr -d ':')"
if [[ "$actual" != "$EXPECTED" ]]; then
  rm -f "$KEYSTORE" "$PROPS"
  echo "fingerprint mismatch -- refusing to leave a wrong key on disk" >&2
  echo "  expected $EXPECTED" >&2
  echo "  actual   ${actual:-<none>}" >&2
  exit 1
fi

echo "Upload key in place, fingerprint verified."
echo "  $KEYSTORE"
echo "  $PROPS"
echo
echo "Build with:  cd android && BORGARLAND_VERSION_NAME=0.1.0 BORGARLAND_VERSION_CODE=1 ./gradlew assembleRelease"
