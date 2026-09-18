#!/bin/bash
set -euo pipefail

identity='Peekaboo Local Development'
keychain="$HOME/Library/Keychains/login.keychain-db"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail 'Peekaboo requires macOS.'
[[ "$EUID" -ne 0 ]] || fail 'Run make as your normal user, without sudo.'
[[ -f "$keychain" ]] || fail 'The login keychain is missing. Create or restore it in Keychain Access.'

umask 077
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/peekaboo-signing.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_signing_access() {
    # Authorize the key before Xcode starts parallel signing jobs.
    cp /usr/bin/true "$temporary_directory/signing-check"
    printf 'Checking signing access. If macOS asks, choose Always Allow for codesign.\n'
    /usr/bin/codesign --force --sign "$identity" --timestamp=none \
        "$temporary_directory/signing-check" 2> "$temporary_directory/signing.log" || {
            cat "$temporary_directory/signing.log" >&2
            fail 'macOS could not use the signing key. Unlock your login keychain and approve codesign access, then retry.'
        }
}

identities=$(/usr/bin/security find-identity -v -p codesigning)
if printf '%s\n' "$identities" | /usr/bin/grep -Fq "\"$identity\""; then
    printf 'Using existing signing identity: %s\n' "$identity"
    check_signing_access
    exit 0
fi

if /usr/bin/security find-certificate -c "$identity" >/dev/null 2>&1; then
    fail "A certificate named '$identity' already exists but is not a valid signing identity. In Keychain Access, check its private key, expiration, and Code Signing trust. Restore the existing identity instead of replacing it to preserve Accessibility grants."
fi

cat > "$temporary_directory/certificate.cnf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no

[subject]
CN = Peekaboo Local Development

[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

printf 'Creating %s in your login keychain. macOS may ask for Keychain access.\n' "$identity"
# Native key import expects the PKCS#1 format emitted by genrsa.
/usr/bin/openssl genrsa -out "$temporary_directory/private.key" 2048 \
    2> "$temporary_directory/openssl.log" || {
        cat "$temporary_directory/openssl.log" >&2
        exit 1
    }
/usr/bin/openssl req -new -x509 -sha256 -days 3650 \
    -config "$temporary_directory/certificate.cnf" \
    -key "$temporary_directory/private.key" \
    -out "$temporary_directory/certificate.pem" \
    2> "$temporary_directory/openssl.log" || {
        cat "$temporary_directory/openssl.log" >&2
        exit 1
    }

# The temporary private key is readable only by this user and removed on exit.
/usr/bin/security import "$temporary_directory/private.key" \
    -k "$keychain" -f openssl -t priv -T /usr/bin/codesign
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign \
    -k "$keychain" "$temporary_directory/certificate.pem"

identities=$(/usr/bin/security find-identity -v -p codesigning)
printf '%s\n' "$identities" | /usr/bin/grep -Fq "\"$identity\"" \
    || fail 'Certificate setup did not produce a valid signing identity. Check Keychain Access before retrying.'
check_signing_access
printf 'Created %s. Future builds will reuse this identity.\n' "$identity"
