#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="cs224n"
ENV_FILE="/home/jovyan/work/CS224N/env.yml"
REQ_FILE="/home/jovyan/work/CS224N/requirements_cs224n.txt"
HASH_FILE="/home/jovyan/.cs224n_env_hash"

# Use a venv so we can install CS224N deps, but with --system-site-packages
# so we don't have to rebuild heavy scientific libs (numpy/scipy/pandas/etc).
VENV_DIR="/home/jovyan/.cs224n/venv"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "CS224N bootstrap: ${ENV_FILE} not found; skipping."
  exit 0
fi

if [[ ! -f "${REQ_FILE}" ]]; then
  echo "CS224N bootstrap: ${REQ_FILE} not found; skipping."
  exit 0
fi

NEW_HASH="$(
  sha256sum "${ENV_FILE}" "${REQ_FILE}" | sha256sum | awk '{print $1}'
)"

OLD_HASH=""
if [[ -f "${HASH_FILE}" ]]; then
  OLD_HASH="$(cat "${HASH_FILE}")"
fi

mkdir -p "$(dirname "${HASH_FILE}")"

if [[ ! -d "${VENV_DIR}" ]] || [[ "${NEW_HASH}" != "${OLD_HASH}" ]]; then
  echo "CS224N bootstrap: (re)building venv at ${VENV_DIR}"
  rm -rf "${VENV_DIR}" || true
  python -m venv --system-site-packages "${VENV_DIR}"

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"
  python -m pip install --no-cache-dir --quiet --upgrade pip
  python -m pip install --no-cache-dir -r "${REQ_FILE}"
  deactivate

  echo "${NEW_HASH}" > "${HASH_FILE}"
fi

# Always (re)install kernel specs because ~/.local can be non-persistent per pod.
source "${VENV_DIR}/bin/activate"
python -m ipykernel install --user --name "${ENV_NAME}" --display-name "Python (${ENV_NAME})"
deactivate

echo "CS224N bootstrap: completed successfully."
