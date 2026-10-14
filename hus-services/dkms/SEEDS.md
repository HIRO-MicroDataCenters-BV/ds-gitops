# DKMS seeds — one-time provisioning

The ds-dkms chart references three Kubernetes `Secret` names:

| Secret               | Keys                 | Consumer   |
|----------------------|----------------------|------------|
| `dkms-witness-seeds` | `witness-seed` (shared) or `witness1`, `witness2`, `witness3` | each witness pod |
| `dkms-watcher-seed`  | `watcher-seed`       | watcher    |
| `dkms-mesagkesto-seed` | `mesagkesto-seed`  | mesagkesto |

The chart never ships plaintext seeds. You generate them once per site and
commit **SealedSecrets** so GitOps can replay the deployment.

## Generation (one-off per site)

```bash
# Install the kli (keri CLI) locally — same version pinned by the chart.
pip install keri==1.3.6

# Deterministic 32-byte seed, base64-wrapped so k8s accepts it as a Secret value.
WITNESS_SEED=$(openssl rand -base64 32)
WATCHER_SEED=$(openssl rand -base64 32)
MESAGKESTO_SEED=$(openssl rand -base64 32)
```

## Sealing (requires the HUS cluster's SealedSecret public cert)

```bash
# dkms-witness-seeds
kubectl create secret generic dkms-witness-seeds \
    --namespace=hus \
    --from-literal=witness-seed="$WITNESS_SEED" \
    --dry-run=client -o yaml \
  | kubeseal --cert hus-sealed-secrets.pub.pem -o yaml \
  > sealed-dkms-witness-seeds.yaml

# dkms-watcher-seed
kubectl create secret generic dkms-watcher-seed \
    --namespace=hus \
    --from-literal=watcher-seed="$WATCHER_SEED" \
    --dry-run=client -o yaml \
  | kubeseal --cert hus-sealed-secrets.pub.pem -o yaml \
  > sealed-dkms-watcher-seed.yaml

# dkms-mesagkesto-seed
kubectl create secret generic dkms-mesagkesto-seed \
    --namespace=hus \
    --from-literal=mesagkesto-seed="$MESAGKESTO_SEED" \
    --dry-run=client -o yaml \
  | kubeseal --cert hus-sealed-secrets.pub.pem -o yaml \
  > sealed-dkms-mesagkesto-seed.yaml
```

Commit the three `sealed-*.yaml` files alongside this README. Fleet picks
them up along with the Helm release.

## First-boot witness AID capture

After the chart deploys, each witness logs its generated AID on startup.
Capture it with:

```bash
kubectl -n hus logs ds-dkms-witness-0 | grep -E "AID|prefix"
```

Then update `watcher.initialOobis` in `values.yaml` so the watcher
subscribes to the witnesses it should trust:

```yaml
watcher:
  initialOobis:
    - "https://dkms-witness-1.hus.nextgen.hiro-develop.nl/oobi/<witness-AID>"
```

## Rotation (post-M36)

Rotating a seed means rotating the AID anchored to it, which breaks every
credential already issued against that AID's current signing key. Plan
rotation ceremonies against the ACDC lifecycle; see ds-credential-issuer
ROADMAP Phase 3.
