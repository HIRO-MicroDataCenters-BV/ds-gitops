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
Secret hus/dkms-seeds, key values.yaml:      ◄── sealed: hus-services/dkms-seeds/sealed-dkms-seeds.yaml
  witness:    { seed: "A…" }                      or created directly (--apply) by an admin
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
# Sealed file, committed to git (needs the SealedSecrets controller)
./scripts/seal-dkms-seeds.sh hus

# Or: create the Secret directly (admin bootstrap; nothing in git)
./scripts/seal-dkms-seeds.sh hus --apply
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
   alias lives on the issuer PVC), then update the trusted-issuer list in
   ds-login.
5. Re-create any test identities.

## Rotation

Changing a seed on purpose (for example after a leak) is a re-key, planned in
advance; see ds-credential-issuer ROADMAP Phase 3.
