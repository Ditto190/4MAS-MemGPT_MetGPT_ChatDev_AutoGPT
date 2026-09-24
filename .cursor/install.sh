#!/usr/bin/env bash
#
# Cloud Agent bootstrap for the 4MAS aggregator repo.
#
# This repository is a meta-project that vendors several AI–agent frameworks as
# git submodules (Autogen, ChatDev, CrewAI, MemGPT, MetaGPT) plus the
# text-generation-webui tool. This script:
#   1. Installs the system toolchains the frameworks need (Python 3.11 for the
#      older frameworks, plus venv/build tooling; Python 3.12 ships in the base
#      image and is used by CrewAI).
#   2. Checks out every submodule so the framework sources are available.
#   3. Creates isolated virtualenvs for the frameworks that install cleanly and
#      installs them, so the environment is immediately usable.
#
# It is safe to run repeatedly (idempotent).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. System dependencies
# ---------------------------------------------------------------------------
# Python 3.11 is required by the older frameworks (pyautogen pins <3.12, and
# MetaGPT/ChatDev/MemGPT pin dependency versions that pre-date 3.12). CrewAI
# works on the base image's Python 3.12.
if ! command -v python3.11 >/dev/null 2>&1; then
  log "Installing Python 3.11 (deadsnakes) and build tooling"
  sudo apt-get update -qq
  sudo apt-get install -y -qq software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    python3.11 python3.11-venv python3.11-dev \
    python3.12-venv \
    build-essential
else
  log "Python 3.11 already present: $(python3.11 --version)"
  # Ensure the venv module for the base Python is available for CrewAI.
  sudo apt-get install -y -qq python3.12-venv >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 2. Submodules (framework sources)
# ---------------------------------------------------------------------------
log "Initializing git submodules"
git submodule sync --recursive
git submodule update --init

# ---------------------------------------------------------------------------
# 3. Per-framework virtualenvs
# ---------------------------------------------------------------------------
# Each framework has conflicting pinned dependencies, so they must live in
# separate virtualenvs rather than a single shared one.
mkdir -p .venvs

create_venv() {
  # $1 = python interpreter, $2 = venv name, $3... = pip install args
  local py="$1" name="$2"; shift 2
  local venv=".venvs/${name}"
  if [ ! -x "${venv}/bin/python" ]; then
    log "Creating ${name} virtualenv (${py})"
    "${py}" -m venv "${venv}"
    "${venv}/bin/python" -m pip install --upgrade pip -q
  fi
  log "Installing ${name} dependencies"
  "${venv}/bin/pip" install "$@"
}

# CrewAI installs cleanly on Python 3.12.
create_venv python3   crewai  ./agents/CrewAI

# AutoGen (pyautogen) requires Python 3.11.
create_venv python3.11 autogen ./agents/Autogen/agents/Autogen

log "Environment setup complete"
echo "Virtualenvs created under .venvs/:"
ls -1 .venvs
cat <<'NOTE'

Additional frameworks (MetaGPT, ChatDev, MemGPT) and the text-generation-webui
tool are checked out under agents/ and tools/. They pin older dependency sets;
install them into their own Python 3.11 virtualenvs as needed, e.g.:

  python3.11 -m venv .venvs/metagpt
  .venvs/metagpt/bin/pip install ./agents/MetaGPT
NOTE
