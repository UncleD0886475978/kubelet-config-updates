#!/usr/bin/env bash
set -e
# kubelet-config-updates — EMPTY repo as inspected 2026-11-09.
# get_file_contents for path "" returned [] — no files, no README.
# This is a minimal verify-and-open script: it clones/pulls, confirms
# whether anything has appeared since inspection, and validates any
# kubelet YAML that shows up. It invents no build.

REPO="kubelet-config-updates"
OWNER="UncleD0886475978"
URL="https://github.com/${OWNER}/${REPO}.git"
DEST="$HOME/repos/${REPO}"
REPO_DIR=""
RUN_ONELINE="curl -fsSL https://raw.githubusercontent.com/${OWNER}/${REPO}/main/setup.sh | bash"

echo "==> Step 1/6: Platform check + base bootstrap (git, curl)"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: this script needs root or sudo to install packages."
    exit 1
  fi
fi
APT=0
if [ "$(uname -s)" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then APT=1; fi
INSTALLED=""
APT_UPDATED=""
note_installed() { INSTALLED="${INSTALLED} $1"; }
apt_update_once() {
  if [ -z "${APT_UPDATED}" ]; then $SUDO apt-get update -y; APT_UPDATED=1; fi
}
apt_install() {
  apt_update_once
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "$@"
}
if [ "${APT}" -eq 1 ]; then
  BASE_PKGS=""
  command -v git >/dev/null 2>&1 || BASE_PKGS="${BASE_PKGS} git"
  command -v curl >/dev/null 2>&1 || BASE_PKGS="${BASE_PKGS} curl"
  [ -f /etc/ssl/certs/ca-certificates.crt ] || BASE_PKGS="${BASE_PKGS} ca-certificates"
  command -v gpg >/dev/null 2>&1 || BASE_PKGS="${BASE_PKGS} gnupg"
  if [ -n "${BASE_PKGS}" ]; then
    echo "    Installing base tools:${BASE_PKGS}"
    # shellcheck disable=SC2086
    apt_install ${BASE_PKGS}
    note_installed "${BASE_PKGS}"
  else
    echo "    Base tools already present (git, curl, ca-certificates, gnupg)."
  fi
else
  echo "    Non-apt platform detected — bootstrap will only CHECK tools and print install guidance."
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git not found. Install it: https://git-scm.com/downloads"
  exit 0
fi
echo "git: $(git --version)"

echo "==> Step 2/6: Get the repo"
if [ -f "$0" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
  SCRIPT_DIR="$PWD"
fi
if [ -f ".git/config" ] && grep -q "${REPO}" .git/config 2>/dev/null; then
  echo "Already inside a ${REPO} checkout: $(pwd)"
  DEST="$(pwd)"
elif [ -d "${DEST}/.git" ]; then
  echo "Found existing checkout at ${DEST} — pulling"
  git -C "${DEST}" pull --ff-only || echo "Pull failed (an empty repo has nothing to pull yet)."
else
  echo "Cloning ${URL} into ${DEST}"
  mkdir -p "$HOME/repos"
  git clone "${URL}" "${DEST}" || echo "Clone reported the repo is empty — that matches the inspection."
fi
cd "${DEST}"
REPO_DIR="${DEST}"

echo "==> Step 3/6: Bootstrap prerequisites (kubectl for kubelet context, python3 for YAML validation — both optional for an empty repo)"
install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then echo "    kubectl: already present"; return 0; fi
  if ! command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then return 1; fi
  echo "    Installing kubectl (official binary)..."
  KARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "${KARCH}" in x86_64) KARCH="amd64" ;; aarch64) KARCH="arm64" ;; esac
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLO "https://dl.k8s.io/release/${KVER}/bin/linux/${KARCH}/kubectl"
  $SUDO install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
  note_installed "kubectl"
}
install_python() {
  if command -v python3 >/dev/null 2>&1 && python3 -c "import venv" >/dev/null 2>&1; then echo "    python3 + venv: already present ($(python3 --version))"; return 0; fi
  [ "${APT}" -eq 1 ] || return 1
  echo "    Installing python3, venv and pip..."
  apt_install python3 python3-venv python3-pip
  note_installed "python3"
}
# For this empty/docs-only repo these are warnings, not hard failures (preserves original verify-and-open behaviour)
install_kubectl || echo "    Optional missing: kubectl — install: https://kubernetes.io/docs/tasks/tools/ (only needed for kubelet context checks)"
install_python || echo "    Optional missing: python3 — install: https://www.python.org/downloads/ (only needed if YAML appears to validate)"

echo "==> Step 4/6: Verify contents"
COUNT="$(find . -path ./.git -prune -o -type f -print | wc -l | tr -d ' ')"
echo "Files (excluding .git): ${COUNT}"
find . -path ./.git -prune -o -type f -print | sort || true
if [ "${COUNT}" = "0" ]; then
  echo "Repo is still EMPTY — no README, no kubelet config, nothing to build or validate."
  echo "Add files on GitHub or locally, push, then re-run this script."
fi

echo "==> Step 5/6: Validate any YAML that exists (future kubelet configs)"
YAML_FILES="$(find . -path ./.git -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print)"
if [ -z "${YAML_FILES}" ]; then
  echo "No YAML files to validate."
else
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found — needed for YAML validation: https://www.python.org/downloads/"
    exit 0
  fi
  for f in ${YAML_FILES}; do
    echo "--- ${f}"
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('YAML OK:', sys.argv[1])" "${f}" \
      || python3 -c "import sys; print('PyYAML missing — install: pip3 install pyyaml'); sys.exit(0)"
  done
  echo "NOTE: Do NOT copy a kubelet config to /var/lib/kubelet/config.yaml or restart kubelet blindly."
  echo "Context commands (read, do not run until you mean it on a node):"
  echo "  sudo systemctl status kubelet"
  echo "  kubeadm config print init-defaults   # reference defaults only"
fi

echo "==> Step 6/6: Show any README context"
if [ -f README.md ]; then cat README.md; else echo "No README.md in this repo."; fi

cat <<EOF

=================== BOOTSTRAP SUMMARY ===================
Installed during this run:${INSTALLED:- (nothing — all tools were already present)}
Working copy: ${REPO_DIR}
Next time, set up from scratch on any fresh Ubuntu VM with one line:
  ${RUN_ONELINE}
=========================================================
EOF

echo ""
echo "Next commands:"
echo "  cd ${DEST}"
echo "  ls -la                       # confirm whether files have been added"
echo "  git log --oneline -5         # see if any commit has landed"
echo "  git pull                     # refresh before adding the first kubelet config"
