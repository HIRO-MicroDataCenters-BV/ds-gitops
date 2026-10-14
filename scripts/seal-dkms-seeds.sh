#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Generate + seal the three DKMS seed secrets for a Hiro site.
#
# Run ONCE per site from a shell with:
#   - kubectl pointed at the site's cluster
#   - kubeseal installed (https://github.com/bitnami-labs/sealed-secrets#installation)
#   - openssl
#
# Writes three sealed-*.yaml files into the matching site's dkms/ directory.
# Review them, commit, PR against develop.
#
# Also prints the plaintext seeds ONCE at the end. Save them in a password
# manager — losing them means losing the AIDs they root. Re-sealing against a
# new cluster cert loses continuity.
#
# Usage:
#   ./scripts/seal-dkms-seeds.sh hus
#   ./scripts/seal-dkms-seeds.sh ki
#   ./scripts/seal-dkms-seeds.sh uva
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SITE="${1:-}"
if [[ -z "$SITE" ]]; then
    echo "usage: $0 <site>   (one of: hus, ki, uva)" >&2
    exit 2
fi

NAMESPACE="$SITE"
OUT_DIR="$SITE-services/dkms"
if [[ ! -d "$OUT_DIR" ]]; then
    echo "error: expected directory $OUT_DIR not found. Run from repo root." >&2
    exit 2
fi

for cmd in kubectl kubeseal openssl; do
    if ! command -v "$cmd" >/dev/null; then
        echo "error: $cmd not installed. See script header." >&2
        exit 2
    fi
done

echo "─── Fetching the site's SealedSecret public cert from the cluster ───"
CERT_FILE="$(mktemp -t sealed-cert.XXXXXX.pem)"
trap 'rm -f "$CERT_FILE"' EXIT
kubeseal --controller-namespace=kube-system --fetch-cert > "$CERT_FILE"
echo "cert: $(wc -l < "$CERT_FILE") lines, SHA1 $(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha1 | cut -d= -f2)"

echo "─── Generating 32-byte random seeds ───"
WITNESS_SEED=$(openssl rand -base64 32)
WATCHER_SEED=$(openssl rand -base64 32)
MESAGKESTO_SEED=$(openssl rand -base64 32)

seal_one() {
    local name="$1"
    local key="$2"
    local value="$3"
    local out="$OUT_DIR/sealed-${name}.yaml"
    echo "─── Sealing ${name} → ${out} ───"
    kubectl create secret generic "$name" \
        --namespace="$NAMESPACE" \
        --from-literal="$key=$value" \
        --dry-run=client -o yaml \
      | kubeseal --cert "$CERT_FILE" -o yaml \
      > "$out"
}

seal_one "dkms-witness-seeds"    "witness-seed"    "$WITNESS_SEED"
seal_one "dkms-watcher-seed"     "watcher-seed"    "$WATCHER_SEED"
seal_one "dkms-mesagkesto-seed"  "mesagkesto-seed" "$MESAGKESTO_SEED"

echo ""
echo "─── Done. Files written: ───"
ls -1 "$OUT_DIR"/sealed-*.yaml

echo ""
echo "─── Plaintext seeds (SAVE THESE SOMEWHERE SAFE, THEN CLEAR THE TERMINAL) ───"
echo "witness:    $WITNESS_SEED"
echo "watcher:    $WATCHER_SEED"
echo "mesagkesto: $MESAGKESTO_SEED"
echo ""
echo "Next: git add $OUT_DIR/sealed-*.yaml && git commit && open a PR."
