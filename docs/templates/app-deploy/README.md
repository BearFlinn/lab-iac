# App Deploy Template

**The canonical template lives at [grizzly-endeavors/app-deploy-template](https://github.com/grizzly-endeavors/app-deploy-template).**

To bootstrap a new application on the cluster:

```bash
gh repo create grizzly-endeavors/<new-app> \
  --template grizzly-endeavors/app-deploy-template \
  --private
```

Then from the new repo's `Actions` tab, dispatch the `deploy` workflow once
with the inputs for your app. That will call the reusable workflow at
[`.github/workflows/register-app.yaml`](../../../.github/workflows/register-app.yaml)
in this repo, which opens an auto-merging PR registering the app with Flux.

After the first registration, every subsequent deploy is automatic: push to
`main` in the app repo, CI builds the image and bumps the tag in
`deploy/values.yaml`, Flux sees the change and reconciles within a minute.

## Architecture

See [ADR-020](../../decisions/020-app-delivery-model.md) for the full
reasoning behind this delivery model. In short:

- Each app repo owns its own `deploy/` directory (Helm chart by default).
- `lab-iac` tracks each app as a thin `GitRepository` + `Kustomization` pair
  under `kubernetes/apps/<app>/`.
- Tag bumps happen inside the app repo's CI — no Flux image automation.
- Every deploy after the first is zero-touch on `lab-iac`.
