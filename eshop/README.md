# eShop lab sources

Source and representation files for the eShop demo. Playbooks: `automation/ansible/playbooks/eshop/`.
Kubernetes manifests: `k8s/eshop/`.

## patches/

Applied in filename order to the pinned upstream commit (`eshop_repo_version`) before each build.
The image tag includes a digest of these files, so editing a patch produces new images.

- `identity-loadgen-client.patch` adds OIDC client `loadgen` to Identity.API
  (`Configuration/Config.cs`): resource-owner password grant, scopes `openid profile orders basket`,
  secret from configuration key `LoadGenClientSecret`. Without that key the client receives a
  random secret and cannot be used. The load generator needs a token that carries a real user's
  `sub` claim, because Ordering.API attributes orders to the caller; upstream eShop only offers
  browser-based (authorization code) clients.

To refresh a patch after changing upstream: edit the file in `~/repos/eShop`, then
`git -C ~/repos/eShop diff > eshop/patches/<name>.patch`.

## loadgen/

`loadgen.py` uses only the Python standard library and runs in `python:3.13-alpine`, mounted
from ConfigMap `eshop-loadgen`. `python loadgen.py --check` places one order and exits 0 once
it reaches `Paid` (used by `test.yml` and `diagnose.yml`).
