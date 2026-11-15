#!/usr/bin/env bash
#
# One-line installer for DOCKER_STARTUP:
#
#   curl -fsSL https://raw.githubusercontent.com/farzanhossan/DOCKER_STARTUP/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/farzanhossan/DOCKER_STARTUP/main/install.sh | bash -s -- postgres redis
#
# Downloads (or updates) the repo into ~/docker-startup and runs ./setup.sh.
# Environment overrides: DOCKER_STARTUP_DIR (install folder), DOCKER_STARTUP_BRANCH (default: main).
#
# Everything is wrapped in main() so a half-downloaded script never runs.
set -euo pipefail

main() {
  local repo="farzanhossan/DOCKER_STARTUP"
  local branch="${DOCKER_STARTUP_BRANCH:-main}"
  local dir="${DOCKER_STARTUP_DIR:-$HOME/docker-startup}"

  if [ -d "$dir/.git" ]; then
    echo "==> Updating $dir"
    git -C "$dir" pull --ff-only --quiet || echo " ! Couldn't update (local changes?). Using the existing copy."
  elif [ -f "$dir/setup.sh" ]; then
    echo "==> Using existing $dir"
  elif [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo " ✖ $dir already exists and isn't DOCKER_STARTUP. Set DOCKER_STARTUP_DIR to another folder." >&2
    exit 1
  elif command -v git >/dev/null 2>&1; then
    echo "==> Downloading DOCKER_STARTUP into $dir"
    git clone --quiet --depth 1 --branch "$branch" "https://github.com/$repo.git" "$dir"
  else
    echo "==> Downloading DOCKER_STARTUP into $dir (git not found, using a tarball)"
    mkdir -p "$dir"
    curl -fsSL "https://github.com/$repo/archive/refs/heads/$branch.tar.gz" | tar -xz -C "$dir" --strip-components=1
  fi

  cd "$dir"
  chmod +x setup.sh

  # Under "curl | bash" stdin is the script itself, so read answers from the terminal instead.
  if [ -t 0 ]; then
    exec bash ./setup.sh "$@"
  elif (: </dev/tty) 2>/dev/null; then
    exec bash ./setup.sh "$@" </dev/tty
  elif [ "$#" -gt 0 ]; then
    exec bash ./setup.sh "$@" # service names / subcommands never need a terminal
  else
    exec bash ./setup.sh --yes # no terminal (CI): use the default selection
  fi
}

main "$@"
