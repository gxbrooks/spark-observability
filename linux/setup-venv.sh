#!/usr/bin/env bash
#
# setup-venv.sh — Recreate the project Python virtual environment from scratch.
#
# Run from the project root or from linux/:
#   bash linux/setup-venv.sh           # interactive (asks for confirmation)
#   bash linux/setup-venv.sh --force   # skip confirmation, always recreate
#   bash linux/setup-venv.sh --check   # report status only, make no changes
#
# This script is the client-side equivalent of the venv setup steps in
# assert_devops_client.sh. Use it when:
#   - The venv was created under a different project path (elastic-on-spark → spark-observability)
#   - The Python version has changed
#   - The venv is corrupt or packages are missing/mismatched
#
# Packages installed:
#   1. spark/requirements/requirements.txt   (base packages: ipython, numpy, pandas, etc.)
#   2. pyyaml toml requests                  (needed by vars/generate_env.py and esapi/kapi)
#   3. flask kubernetes                       (API server and K8s client)
#   4. pyspark==<SPARK_VERSION>              (must match cluster spark version)
#   5. google-cloud-bigquery and friends     (BigQuery connector for GCS integrations)
#   6. scikit-learn scipy                    (ML packages)
#

set -euo pipefail

FORCE=false
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    --check|-c) CHECK=true ;;
    --help|-h)
      head -20 "$0" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# Resolve project root (works from any directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${ROOT_DIR}/venv"

echo "========================================"
echo "  Spark Observability - venv setup"
echo "  Project root: ${ROOT_DIR}"
echo "  Venv path:    ${VENV_DIR}"
echo "========================================"

# --- Read Python and Spark versions from variables.yaml -----------------------
PYTHON_VERSION="3.11"   # project default
SPARK_VERSION="4.0.1"   # project default

VARS_FILE="${ROOT_DIR}/vars/variables.yaml"
if [[ -f "${VARS_FILE}" ]]; then
  # variables.yaml uses block style: PYTHON_VERSION:\n  value: 3.11
  _py=$(awk '/^PYTHON_VERSION:/{found=1} found && /value:/{print $2; exit}' "${VARS_FILE}" | tr -d '"' | tr -d "'")
  _sp=$(awk '/^SPARK_VERSION:/{found=1} found && /value:/{print $2; exit}' "${VARS_FILE}" | tr -d '"' | tr -d "'")
  [[ -n "${_py}" ]] && PYTHON_VERSION="${_py}"
  [[ -n "${_sp}" ]] && SPARK_VERSION="${_sp}"
fi

PYTHON_CMD="python${PYTHON_VERSION}"
echo "Info    : Python version: ${PYTHON_VERSION}  (command: ${PYTHON_CMD})"
echo "Info    : Spark version:  ${SPARK_VERSION}"

# --- Verify Python binary exists ----------------------------------------------
if ! command -v "${PYTHON_CMD}" &>/dev/null; then
  echo "Error   : ${PYTHON_CMD} not found. Install it first:"
  echo "          sudo apt install python${PYTHON_VERSION} python${PYTHON_VERSION}-venv"
  exit 1
fi

# --- Check mode ---------------------------------------------------------------
if ${CHECK}; then
  echo ""
  echo "--- Check mode (no changes) ---"
  if [[ -d "${VENV_DIR}" ]]; then
    CURRENT_VER=$("${VENV_DIR}/bin/python" --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
    CURRENT_VENV=$(grep '^VIRTUAL_ENV=' "${VENV_DIR}/bin/activate" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"')
    echo "Venv exists:   ${VENV_DIR}"
    echo "Python ver:    ${CURRENT_VER} (required: ${PYTHON_VERSION})"
    echo "VIRTUAL_ENV:   ${CURRENT_VENV}"
    if grep -q "elastic-on-spark" "${VENV_DIR}/bin/activate" 2>/dev/null; then
      echo "WARNING: activate script still references elastic-on-spark path → run without --check to fix"
    fi
    PY_INSTALLED=$("${VENV_DIR}/bin/python" -c "import pyspark; print(pyspark.__version__)" 2>/dev/null || echo "not installed")
    echo "PySpark:       ${PY_INSTALLED} (required: ${SPARK_VERSION})"
  else
    echo "Venv not found at ${VENV_DIR}"
  fi
  exit 0
fi

# --- Confirmation prompt (unless --force) -------------------------------------
if [[ -d "${VENV_DIR}" ]] && ! ${FORCE}; then
  echo ""
  echo "WARNING: This will DELETE and RECREATE ${VENV_DIR}"
  echo "         All installed packages will be reinstalled."
  read -p "Continue? [y/N] " -n 1 -r; echo
  if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# --- Save current packages before deleting -----------------------------------
FREEZE_BACKUP="${ROOT_DIR}/linux/.venv-freeze-backup.txt"
if [[ -d "${VENV_DIR}" ]] && [[ -x "${VENV_DIR}/bin/pip" ]]; then
  echo "Info    : Saving current package list to ${FREEZE_BACKUP}..."
  "${VENV_DIR}/bin/pip" freeze > "${FREEZE_BACKUP}" 2>/dev/null || true
fi

# --- Remove old venv ----------------------------------------------------------
if [[ -d "${VENV_DIR}" ]]; then
  echo "Info    : Removing old venv..."
  rm -rf "${VENV_DIR}"
fi

# --- Create new venv ----------------------------------------------------------
echo "Info    : Creating new Python ${PYTHON_VERSION} venv at ${VENV_DIR}..."
"${PYTHON_CMD}" -m venv "${VENV_DIR}"

echo "Info    : VIRTUAL_ENV is now: $(grep '^VIRTUAL_ENV=' "${VENV_DIR}/bin/activate" | head -1 | cut -d= -f2)"

# --- Upgrade pip --------------------------------------------------------------
echo "Info    : Upgrading pip..."
"${VENV_DIR}/bin/pip" install --quiet --upgrade pip

# --- Install base requirements -----------------------------------------------
REQS="${ROOT_DIR}/spark/requirements/requirements.txt"
if [[ -f "${REQS}" ]]; then
  echo "Info    : Installing base requirements from ${REQS}..."
  "${VENV_DIR}/bin/pip" install --quiet -r "${REQS}" || \
    "${VENV_DIR}/bin/pip" install -r "${REQS}"   # retry with output on failure
else
  echo "Warning : ${REQS} not found — skipping base requirements"
fi

# --- Install additional packages ----------------------------------------------
echo "Info    : Installing additional packages (pyyaml, toml, requests, flask, kubernetes)..."
"${VENV_DIR}/bin/pip" install --quiet pyyaml toml requests flask kubernetes

echo "Info    : Installing data/ML packages (numpy, pandas, scikit-learn, scipy, pyarrow)..."
"${VENV_DIR}/bin/pip" install --quiet --upgrade numpy pandas scikit-learn scipy pyarrow

echo "Info    : Installing Google Cloud packages (BigQuery)..."
"${VENV_DIR}/bin/pip" install --quiet \
  google-cloud-bigquery google-cloud-bigquery-storage db-dtypes || true

echo "Info    : Installing PySpark ${SPARK_VERSION}..."
"${VENV_DIR}/bin/pip" install --quiet "pyspark==${SPARK_VERSION}"

# --- Verify -------------------------------------------------------------------
echo ""
echo "--- Verification ---"
INSTALLED_PY=$("${VENV_DIR}/bin/python" --version 2>&1)
INSTALLED_SP=$("${VENV_DIR}/bin/python" -c "import pyspark; print(pyspark.__version__)" 2>/dev/null || echo "FAILED")
INSTALLED_NP=$("${VENV_DIR}/bin/python" -c "import numpy; print(numpy.__version__)" 2>/dev/null || echo "FAILED")
VIRTUAL_ENV_VAL=$(grep '^VIRTUAL_ENV=' "${VENV_DIR}/bin/activate" | head -1 | cut -d= -f2)

echo "Python:        ${INSTALLED_PY}"
echo "PySpark:       ${INSTALLED_SP}"
echo "NumPy:         ${INSTALLED_NP}"
echo "VIRTUAL_ENV:   ${VIRTUAL_ENV_VAL}"

OLD_REFS=$(grep -rl "elastic-on-spark" "${VENV_DIR}/bin/" 2>/dev/null | wc -l)
if [[ "${OLD_REFS}" -gt 0 ]]; then
  echo "WARNING: ${OLD_REFS} file(s) still reference elastic-on-spark — unexpected"
else
  echo "Path check:    OK (no elastic-on-spark references)"
fi

echo ""
echo "Done. Open a new terminal (or run: exec bash) to activate the new venv."
echo "To activate manually: source ${VENV_DIR}/bin/activate"
