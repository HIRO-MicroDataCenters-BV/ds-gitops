#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Generate the DKMS seeds for one Hiro site and deliver them as the Secret
# `dkms-seeds` (key `values.yaml`), which Fleet merges into the ds-dkms Helm
# values via `helm.valuesFrom` (see <site>-services/dkms/fleet.yaml).
#
# Each seed fixes the AID of the witness, watcher or mesagkesto. Run this ONCE
# per site and keep the seeds forever: a new seed is a new AID, and every KEL
# anchored at the old witness stops verifying.
#
# Two modes:
#   ./scripts/seal-dkms-seeds.sh hus           write <site>-services/dkms-seeds/sealed-dkms-seeds.yaml
#                                              (needs kubeseal + the cluster's SealedSecrets controller;
#                                              commit the file, Fleet applies it)
#   ./scripts/seal-dkms-seeds.sh hus --apply   create the Secret directly in the current kubectl
#                                              context (admin bootstrap before SealedSecrets exists,
#                                              or a local kind cluster). Nothing is written to git.
#
# Needs: kubectl, and HCF's `dkms` CLI (seeds must be 44-char KERI qb64 Ed25519
# seeds, which is what `dkms key seed` prints; `openssl rand -base64` is not).
#
# The plaintext seeds are written ONCE to a 0600 file in $HOME, never printed.
# Move them into the password manager, then delete the file. Losing them means
# losing the AIDs they root.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SITE="${1:-}"
MODE="${2:-seal}"
if [[ -z "$SITE" || ( "$MODE" != "seal" && "$MODE" != "--apply" ) ]]; then
    echo "usage: $0 <site> [--apply]   (site: hus, ki or uva)" >&2
    exit 2
fi
NAMESPACE="$SITE"
OUT_DIR="$SITE-services/dkms-seeds"
if [[ ! -d "$SITE-services" ]]; then
    echo "error: $SITE-services not found. Run from the ds-gitops repo root." >&2
    exit 2
fi

NEEDED=(kubectl dkms)
[[ "$MODE" == "seal" ]] && NEEDED+=(kubeseal)
for cmd in "${NEEDED[@]}"; do
    if ! command -v "$cmd" >/dev/null; then
        echo "error: $cmd not installed. See script header." >&2
        exit 2
    fi
done

echo "─── Target: context $(kubectl config current-context), namespace $NAMESPACE, mode $MODE ───"
read -r -p "Generate NEW DKMS seeds for this target? [y/N] " ok
[[ "$ok" == "y" || "$ok" == "Y" ]] || { echo "aborted"; exit 1; }
if kubectl -n "$NAMESPACE" get secret dkms-seeds >/dev/null 2>&1; then
    echo "error: Secret $NAMESPACE/dkms-seeds already exists. Seeds are generated once;" >&2
    echo "       replacing them changes every DKMS AID. Delete it first only if you mean to re-key." >&2
    exit 1
fi

new_seed() {
    # dkms prints a log line before the seed; keep the last line only.
    local s
    s="$(dkms key seed 2>/dev/null | tail -1)"
    if [[ ! "$s" =~ ^A[A-Za-z0-9_-]{43}$ ]]; then
        echo "error: dkms key seed did not return a 44-char qb64 Ed25519 seed" >&2
        exit 1
    fi
    printf '%s' "$s"
}

umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
VALUES="$WORK/values.yaml"
cat > "$VALUES" <<EOF
witness:
  seed: "$(new_seed)"
watcher:
  seed: "$(new_seed)"
mesagkesto:
  seed: "$(new_seed)"
EOF

BACKUP="$HOME/dkms-seeds-$SITE-$(date +%Y%m%d-%H%M%S).yaml"
cp "$VALUES" "$BACKUP"
chmod 600 "$BACKUP"

secret_yaml() {
    kubectl create secret generic dkms-seeds \
        --namespace="$NAMESPACE" \
        --from-file=values.yaml="$VALUES" \
        --dry-run=client -o yaml
}

if [[ "$MODE" == "--apply" ]]; then
    echo "─── Creating Secret $NAMESPACE/dkms-seeds in the cluster ───"
    secret_yaml | kubectl apply -f -
else
    echo "─── Sealing against the site's SealedSecrets controller ───"
    mkdir -p "$OUT_DIR"
    secret_yaml | kubeseal --controller-namespace=kube-system -o yaml > "$OUT_DIR/sealed-dkms-seeds.yaml"
    echo "wrote $OUT_DIR/sealed-dkms-seeds.yaml"
fi

echo ""
echo "─── Done ───"
echo "Plaintext seeds: $BACKUP (mode 600)."
echo "Move them into the password manager now, then delete that file."
echo ""
echo "Next (re-key — see $SITE-services/dkms/SEEDS.md):"
echo "  1. wipe the witness and watcher PVCs, redeploy ds-dkms"
echo "  2. read the new watcher AID and update watcher OOBIs in values.yaml"
echo "  3. re-create the credential issuer's identity on the new witness"
