#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Generate + seal the RSA private key ds-login signs JWTs with.
#
# ds-login's values.yaml references a Secret named `ds-login-signing-key`
# with a `private.pem` entry holding a PKCS8-encoded RSA private key. The
# chart mounts the Secret at /etc/ds-login/signing-key/ and the app reads
# it via DS__JWT_PRIVATE_KEY_PEM_PATH.
#
# Run ONCE per site from a shell with kubectl, kubeseal and openssl, pointed
# at the target cluster. Writes a sealed-ds-login-signing-key.yaml next to
# this script which you then move into <site>-services/login/ and commit.
#
# Keep the plaintext key! Rotating it means every active JWT becomes
# unverifiable immediately — plan rotation ceremonies carefully.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SITE="${1:-}"
if [[ -z "$SITE" ]]; then
    echo "usage: $0 <site>   (one of: hus, ki, uva)" >&2
    exit 2
fi

NAMESPACE="$SITE"
OUT_DIR="$SITE-services/login"
if [[ ! -d "$OUT_DIR" ]]; then
    echo "error: expected directory $OUT_DIR not found. Run from repo root." >&2
    exit 2
fi

for cmd in kubectl kubeseal openssl; do
    if ! command -v "$cmd" >/dev/null; then
        echo "error: $cmd not installed." >&2
        exit 2
    fi
done

CERT_FILE="$(mktemp -t sealed-cert.XXXXXX.pem)"
KEY_FILE="$(mktemp -t ds-login-signing.XXXXXX.pem)"
trap 'rm -f "$CERT_FILE" "$KEY_FILE"' EXIT

echo "─── Fetching the site's SealedSecret public cert from the cluster ───"
kubeseal --controller-namespace=kube-system --fetch-cert > "$CERT_FILE"

echo "─── Generating 2048-bit RSA key (PKCS8) ───"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEY_FILE"

echo "─── Sealing → $OUT_DIR/sealed-ds-login-signing-key.yaml ───"
kubectl create secret generic ds-login-signing-key \
    --namespace="$NAMESPACE" \
    --from-file=private.pem="$KEY_FILE" \
    --dry-run=client -o yaml \
  | kubeseal --cert "$CERT_FILE" -o yaml \
  > "$OUT_DIR/sealed-ds-login-signing-key.yaml"

echo ""
echo "─── Done. Written: $OUT_DIR/sealed-ds-login-signing-key.yaml ───"
echo ""
echo "─── Plaintext key fingerprint (OK to log; not the key itself) ───"
openssl rsa -in "$KEY_FILE" -noout -pubout | openssl md5 || true
echo ""
echo "─── BACK UP THE PLAINTEXT KEY somewhere only you can access ───"
echo "    Rotating this key invalidates every active ds-login JWT instantly."
echo "    cat $KEY_FILE"
