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

echo "==> Step 1/5: Check prerequisites"
if ! command -v git >/dev/null 2>&1; then
  echo "git not found. Install it: https://git-scm.com/downloads"
  exit 0
fi
echo "git: $(git --version)"

echo "==> Step 2/5: Get the repo"
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

echo "==> Step 3/5: Verify contents"
COUNT="$(find . -path ./.git -prune -o -type f -print | wc -l | tr -d ' ')"
echo "Files (excluding .git): ${COUNT}"
find . -path ./.git -prune -o -type f -print | sort || true
if [ "${COUNT}" = "0" ]; then
  echo "Repo is still EMPTY — no README, no kubelet config, nothing to build or validate."
  echo "Add files on GitHub or locally, push, then re-run this script."
fi

echo "==> Step 4/5: Validate any YAML that exists (future kubelet configs)"
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

echo "==> Step 5/5: Show any README context"
if [ -f README.md ]; then cat README.md; else echo "No README.md in this repo."; fi

echo ""
echo "Next commands:"
echo "  cd ${DEST}"
echo "  ls -la                       # confirm whether files have been added"
echo "  git log --oneline -5         # see if any commit has landed"
echo "  git pull                     # refresh before adding the first kubelet config"
