# DKMS seeds — one-time provisioning

Each KERI seed fixes one AID: the witness's, the watcher's and mesagkesto's.
Every identity anchored at the witness (the credential issuer, every user)
names that witness AID in its KEL. So a site's seeds are generated **once**,
kept **forever**, and are **different per site**.

This repo is public: seeds never go into it in plaintext.

## How the seeds reach the chart

```
scripts/seal-dkms-seeds.sh hus
        │  generates 3 seeds with `dkms key seed`
        ▼
Secret hus/dkms-seeds, key values.yaml:      ◄── created directly (--apply) by a cluster admin
  witness:    { seed: "A…" }                      (HUS, 28 Oct 2026), or later a SealedSecret
  watcher:    { seed: "A…" }
  mesagkesto: { seed: "A…" }
        │  Fleet helm.valuesFrom (hus-services/dkms/fleet.yaml)
        ▼
ds-dkms chart → witness.yml / watcher.yml / messagebox.yml
```

The chart (from 0.1.4) has no seed defaults and refuses to render without
them. Chart 0.1.3 still carries HCF's public demo seeds as defaults; with
`valuesFrom` in place they are overridden, so the order of upgrades does not
matter.

## Generate (once per site)

Requirements: `kubectl` pointed at the site's cluster, HCF's `dkms` CLI, and —
for the sealed variant — `kubeseal` plus the SealedSecrets controller on the
cluster.

```bash
# Create the Secret directly (cluster admin; nothing in git) — used for HUS
./scripts/seal-dkms-seeds.sh hus --apply

# Or: a sealed file to commit (needs kubeseal + the SealedSecrets controller,
# which HUS does not have yet). It is written to <site>-services/dkms-seeds/;
# that folder then needs its own fleet.yaml, and dkms/fleet.yaml a dependsOn
# on it, so the Secret exists before ds-dkms renders.
./scripts/seal-dkms-seeds.sh hus
```

The script refuses to run if `dkms-seeds` already exists. It writes the
plaintext seeds once to a mode-600 file in `$HOME`: move them into the password
manager and delete the file. Without them, a lost cluster means lost AIDs.

Seeds must be KERI qb64 Ed25519 seeds (44 chars, starting with `A`), which is
what `dkms key seed` prints. `openssl rand -base64 32` is not that format.

## Re-key after the seeds change

New seeds mean new AIDs. Everything tied to the old ones must be redone:

1. Delete the witness and watcher PVCs, then redeploy ds-dkms.
2. Read the new AIDs:
   ```bash
   kubectl -n hus run aid-check --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
     sh -c 'curl -s http://ds-dkms-witness-1:3232/introduce; echo; curl -s http://ds-dkms-watcher:3235/introduce'
   ```
3. Put the new watcher AID into `mesagkesto.watcherOobi` in `values.yaml`.
4. Re-create the credential issuer's identity on the new witness (its dkms
   alias lives on the issuer PVC):
   ```bash
   kubectl -n hus exec deploy/ds-credential-issuer -- sh -c \
     'mv /var/lib/ds-credential-issuer/dkms/.dkms-dev-cli/hus-issuer /var/lib/ds-credential-issuer/hus-issuer.old'
   kubectl -n hus rollout restart deploy/ds-credential-issuer
   kubectl -n hus logs deploy/ds-credential-issuer | grep "issuer ready"
   ```
5. Put the new issuer AID into `trustedIssuerAids` in
   `hus-services/login/values.yaml`. Until it is deployed, every login is
   rejected ("not on this verifier's trusted-issuer allowlist").
6. Re-create identities anchored at the old witness: the operator
   (`operator-dkms` PVC) and test holders (`e2e-holder-dkms`), then re-issue the
   operator credential from the new issuer.

## Rotation

Changing a seed on purpose (for example after a leak) is a re-key, planned in
advance; see ds-credential-issuer ROADMAP Phase 3.
