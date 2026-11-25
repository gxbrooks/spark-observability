#!/usr/bin/env bash
# Print TF_VAR_SN_* export lines for the active brooks-lab ServiceNow instance (or SN_TARGET).
# Usage (from automation/terraform/servicenow): eval "$(scripts/sn-env.sh)"
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
"$root/venv/bin/python" -I - "$root" <<'PY'
import shlex, sys, pathlib, yaml
root = pathlib.Path(sys.argv[1]); sys.path.insert(0, str(root))
from servicenow.sn_active_instance import active_instance
inst = active_instance(root)
sfx = inst.get("secrets_suffix") or ""
sn = yaml.safe_load((root / "vars/secrets.yaml").read_text())["servicenow"]
for k, v in (("SN_URL", inst["url"].rstrip("/")), ("SN_USER", sn.get("SN_USER" + sfx) or sn["SN_USER"]),
             ("SN_PASSWORD", sn.get("SN_PASSWORD" + sfx) or sn["SN_PASSWORD"])):
    print(f"export TF_VAR_{k}={shlex.quote(v)}")
PY
