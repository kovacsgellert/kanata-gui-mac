#!/bin/bash
# One-time: create the self-signed code-signing certificate releases are
# signed with. A stable signature lets macOS keep privacy grants (e.g.
# Accessibility) across updates; ad-hoc signatures change with every build.
# App-neutral: one certificate is shared by all of the author's Mac apps,
# since grants are keyed on bundle id + certificate.
# Usage: [CN="Name Code Signing"] ./scripts/make-signing-cert.sh [out-dir]   (default ~/.codesign)
# Writes signing.p12 + its password; back both up. Losing them means a new
# certificate, and every user of every app has to re-grant permissions once.
set -euo pipefail
OUT="${1:-$HOME/.codesign}"
CN="${CN:-Gellért Kovács Code Signing}"

test ! -e "$OUT/signing.p12" || { echo "ERROR: $OUT/signing.p12 already exists" >&2; exit 1; }
mkdir -p "$OUT"
chmod 700 "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
utf8 = yes
string_mask = utf8only
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CN
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# System LibreSSL: its PKCS#12 encryption is one `security import` accepts.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASSWORD="$(/usr/bin/openssl rand -base64 24)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$CN" -passout "pass:$PASSWORD" -out "$OUT/signing.p12"
printf '%s' "$PASSWORD" > "$OUT/signing.p12.password"
chmod 600 "$OUT/signing.p12" "$OUT/signing.p12.password"

echo "Wrote $OUT/signing.p12 and $OUT/signing.p12.password (valid 20 years)."
echo "Add them as GitHub Actions secrets:"
echo "  base64 -i \"$OUT/signing.p12\" | gh secret set SIGNING_P12_BASE64"
echo "  gh secret set SIGNING_P12_PASSWORD < \"$OUT/signing.p12.password\""
