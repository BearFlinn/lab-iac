# Runbook: OpenBao disaster recovery

When OpenBao is down, sealed, unreachable, or has lost its data. Covers every major "OpenBao is broken" scenario.

See also: `docs/decisions/023-self-hosted-openbao-on-r730xd.md` for the architectural context, and `docs/runbooks/openbao-rotation.md` for planned key rotation.

## Manual prerequisites (one-time Infisical setup)

Before `deploy-openbao.yml` can run, there must be an Infisical project with a universal-auth machine identity. This is the only piece of the stack that is not captured as IaC (Infisical configuration sits outside this repo). The actual project used is the one referenced by `workspaceId` in `.infisical.json` at the repo root.

1. Log in to Infisical (https://app.infisical.com) as Bear.
2. Either reuse the existing lab-iac project (whose ID is in `.infisical.json`) or create a new one and update that file's `workspaceId` to match.
3. Ensure the project has an environment with slug `prod` (the role's `openbao_infisical_env` default).
4. Organization → Access Control → Identities → Create Identity:
   - Name: `openbao-r730xd` (or similar)
   - Authentication method: Universal Auth
   - Client Secret TTL: no expiry (rotation is manual, see rotation runbook)
   - Access scope: the project from step 2, environment `prod`
   - Role: read+write on `prod` secrets (the built-in "Admin" role works). The identity needs write because rotation pushes new keys back.
5. Copy the Client ID and Client Secret.
6. Back in the repo, write them into the encrypted vault:
   ```
   ./scripts/set-openbao-bootstrap-secrets.sh
   ```
   Prompts for both values. Upserts `vault_infisical_openbao_client_id` / `_client_secret` and re-encrypts `vault.yml` in place.
7. The controller running `bootstrap-openbao.yml` / rotation playbooks needs write access to the same project. In practice this is your workstation — `infisical login` once and the CLI keeps the token in the system keyring. The bootstrap playbook's first task verifies the controller can read from the project and fails loudly if not.

Only after these steps is the playbook path usable.

## Scenario: R730xd rebooted, OpenBao is sealed

First choice: let the auto-unseal service recover on its own. Check:
```
ssh r730xd 'systemctl status foundation-openbao openbao-auto-unseal'
ssh r730xd 'journalctl -u openbao-auto-unseal -n 100 --no-pager'
ssh r730xd 'bao status'
```

If `openbao-auto-unseal.service` is `failed`, usually the cause is:
- Infisical unreachable (R730xd has no internet): `ssh r730xd 'curl -v https://app.infisical.com'`
- `/etc/openbao/infisical-auth.env` has stale creds (secret was rotated but env file wasn't updated): re-run `deploy-openbao.yml`.
- Infisical project was renamed or the machine identity revoked.

If none of those, unseal by hand:
```
ssh r730xd
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/etc/openbao/tls/ca.crt
# Get keys from your password manager OR from Infisical directly from your laptop:
bao operator unseal <key1>
bao operator unseal <key2>
bao operator unseal <key3>
bao status   # Sealed: false
```

## Scenario: Infisical project deleted or access lost

**This is the worst case short of losing Raft data.** If the unseal keys are gone from Infisical AND R730xd reboots, there is no scripted recovery.

Recovery path:
1. Retrieve the unseal keys from the password-manager backup created during `bootstrap-openbao.yml`.
2. Rebuild the Infisical project (follow "Manual prerequisites" above).
3. If the new project has a different workspace ID, update `.infisical.json` at the repo root so `vars.yml` picks it up automatically.
4. Push the recovered keys back, making sure to use `--type=shared` so the universal-auth machine identity can read them:
```
PID=$(jq -r .workspaceId .infisical.json)
for i in 1 2 3 4 5; do
  infisical secrets set --projectId="$PID" --env=prod --type=shared \
    "OPENBAO_UNSEAL_KEY_${i}=<key>"
done
infisical secrets set --projectId="$PID" --env=prod --type=shared \
  "OPENBAO_ROOT_TOKEN=<root-token>"
```
5. Re-run `deploy-openbao.yml` (idempotent) so the new machine-identity creds land on r730xd, then restart `openbao-auto-unseal.service`.

If the password-manager backup is also lost: the data is unrecoverable. You will have to `rm -rf /mnt/zfs/foundation/openbao/data`, re-run `deploy-openbao.yml` + `bootstrap-openbao.yml`, and re-provision every secret inside OpenBao from scratch.

## Scenario: Raft data corruption

Symptoms: OpenBao container keeps restarting, logs mention "raft backend cannot start", "failed to open boltdb", etc.

1. Stop the container:
```
ssh r730xd 'systemctl stop foundation-openbao'
```
2. Roll back to the most recent healthy ZFS snapshot:
```
ssh r730xd 'zfs list -t snapshot | grep foundation/openbao/data'
ssh r730xd 'zfs rollback tank/foundation/openbao/data@<snapshot-name>'
```
3. Start and unseal:
```
ssh r730xd 'systemctl start foundation-openbao openbao-auto-unseal'
ssh r730xd 'bao status'
```

If ZFS snapshots don't exist (or all corrupt), restore from the daily Raft snapshot taken by `/opt/foundation/openbao/openbao-backup.sh`:
```
ssh r730xd
systemctl stop foundation-openbao openbao-auto-unseal
# keep the corrupted data dir out of the way in case forensics are needed
mv /mnt/zfs/foundation/openbao/data /mnt/zfs/foundation/openbao/data.broken-$(date +%s)
mkdir -p /mnt/zfs/foundation/openbao/data
systemctl start foundation-openbao
# wait for API to be reachable, then:
bao operator raft snapshot restore \
  -force \
  /mnt/zfs/foundation/openbao/backup/openbao-raft-<timestamp>.snap
systemctl start openbao-auto-unseal
```

After restore, all tokens are invalidated — mint a new root-token-equivalent via generate-root (see rotation runbook flow 2) or use the root token that came out of the original bootstrap.

## Scenario: R730xd rebuild from bare metal

1. Base OS + Docker + ZFS per the usual R730xd playbooks (`setup-r730xd.yml`, `r730xd-zfs.yml`).
2. Restore `/mnt/zfs/foundation/openbao/data` from the most recent ZFS snapshot OR `/mnt/zfs/foundation/openbao/backup/` if stored off-box.
3. Run `deploy-openbao.yml` — role is idempotent and will reattach to the existing Raft data.
4. Let `openbao-auto-unseal.service` fire; verify `bao status` reports unsealed.

If the Raft data is completely lost (no ZFS snapshot, no off-box backup), treat it as "secrets gone" — go through the bootstrap flow again and re-provision every consumer.

## Scenario: TLS cert expiry or hostname change

The role regenerates the cert if it's within 30 days of expiry. To force early renewal:
```
ssh r730xd 'rm /etc/openbao/tls/server.crt /etc/openbao/tls/server.key'
ansible-playbook ansible/playbooks/deploy-openbao.yml \
  --vault-password-file .vault_pass -v
```
Role will mint a new leaf from the existing CA and restart the server. Consumers that trust the CA bundle don't need any changes. If the CA itself was regenerated (e.g., the CA key was rotated too), every consumer's CA trust needs to be refreshed.

## Common signals → what to check

| Symptom | First command |
|---|---|
| `OpenbaoUnavailable` alert | `ssh r730xd 'systemctl status foundation-openbao openbao-auto-unseal'` |
| `OpenbaoAutoUnsealFailed` alert | `ssh r730xd 'journalctl -u openbao-auto-unseal -n 100'` |
| `OpenbaoAuditLogDiskFull` alert | `ssh r730xd 'df -h /mnt/zfs && ls -lh /mnt/zfs/foundation/openbao/audit/'` |
| Clients can't verify TLS | `openssl s_client -showcerts -connect 10.0.0.200:8200 -servername r730xd.lab` |
| Container keeps restarting | `ssh r730xd 'docker logs foundation-openbao --tail 200'` |
