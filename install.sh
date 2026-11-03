#!/bin/bash
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { printf 'USER: Run installer on macOS host.\n' >&2; exit 1; }
INSTALL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.local/share/rcu"
LINK="$HOME/.local/bin/rcu"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rcu"
ZSHRC="$HOME/.zshrc"
MARKER='# rcu-cli: managed PATH'
msg() { if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then gum style --foreground 39 "$*"; else printf '%s\n' "$*"; fi; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# P0 – Safe uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
  # 1. Symlink: only remove if it points to our prefix
  if [[ -L "$LINK" ]]; then
    local target
    target="$(readlink "$LINK")"
    # Canonicalise: both must resolve to the same real path
    if [[ "$target" == "$PREFIX/bin/rcu" ]] || [[ "$(realpath "$target" 2>/dev/null || true)" == "$(realpath "$PREFIX/bin/rcu" 2>/dev/null || true)" ]]; then
      unlink "$LINK"
      msg "Removed symlink: $LINK"
    else
      msg "Symlink $LINK points to '$target' – not managed by rcu, leaving it."
    fi
  elif [[ -e "$LINK" ]]; then
    # Regular file at $LINK – NOT ours. Fail-closed.
    msg "File exists at $LINK but is not our symlink – skipping."
  fi

  # 2. zshrc: remove only our managed block
  if [[ -f "$ZSHRC" ]] && grep -Fxq "$MARKER" "$ZSHRC"; then
    local tmp
    tmp="$(mktemp "$HOME/.zshrc.rcu.XXXXXX")" || fail "Cannot create temp file for zshrc"
    awk -v m="$MARKER" '$0==m {skip=1;next} skip==1 {skip=0;next} {print}' "$ZSHRC" > "$tmp"
    chmod --reference="$ZSHRC" "$tmp" 2>/dev/null || chmod 600 "$tmp"
    mv -f "$tmp" "$ZSHRC"
    msg "Removed rcu PATH block from $ZSHRC"
  fi

  # 3. Do NOT delete $PREFIX or $CONF_DIR – user data and config are preserved.
  msg "Local configuration ($CONF_DIR) and data ($PREFIX) are preserved."
  msg "To remove them manually: rm -rf '$CONF_DIR' '$PREFIX'"
  exit 0
}

if [[ "${1:-}" == --uninstall ]]; then
  do_uninstall
fi

# ---------------------------------------------------------------------------
# P0 – Atomic install with staging, integrity, and rollback
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] || fail 'Use ./install.sh or ./install.sh --uninstall'

# --- Pre-flight checks (no mutation yet) ---
[[ -d /Applications/UTM.app && -x /Applications/UTM.app/Contents/MacOS/utmctl ]] \
  || fail 'UTM installation missing: install UTM first; existing VM will not be modified.'
msg 'UTM found.'

if ! command -v brew >/dev/null 2>&1; then
  msg 'USER: Homebrew is missing; the official Homebrew installer may ask for your macOS password. Follow its prompts.'
  NONINTERACTIVE=0 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || fail 'Homebrew installation failed'
  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_path" ]]; then eval "$("$brew_path" shellenv)"; break; fi
  done
fi
command -v brew >/dev/null 2>&1 || fail 'Homebrew unavailable'
if ! command -v gum >/dev/null 2>&1; then
  msg 'Installing gum via Homebrew'; brew install gum || fail 'gum installation failed'
fi

# P1 – Installer conflicts: never overwrite a foreign launcher
if [[ -e "$LINK" ]]; then
  if [[ -L "$LINK" ]]; then
    local_target="$(readlink "$LINK" 2>/dev/null || true)"
    if [[ "$local_target" != "$PREFIX/bin/rcu" ]]; then
      fail "Symlink $LINK already points to '$local_target' – not managed by rcu. Remove it first."
    fi
  else
    fail "Regular file at $LINK – not managed by rcu. Remove it first."
  fi
fi

# P1 – Directory collision
if [[ -e "$PREFIX" ]]; then
  [[ -f "$PREFIX/.rcu-managed" ]] || fail "Directory collision: $PREFIX exists but is not managed by rcu."
fi

# --- Package integrity ---
for p in bin/rcu lib/core.sh lib/backends/utm.sh config/config.example; do
  [[ -f "$INSTALL_ROOT/$p" ]] || fail "Missing package file: $p"
done
/bin/bash -n "$INSTALL_ROOT/bin/rcu" "$INSTALL_ROOT/lib/core.sh" "$INSTALL_ROOT/lib/backends/utm.sh" \
  || fail 'Bash syntax validation failed'

# --- Staging ---
mkdir -p "$HOME/.local/bin" "$HOME/.local/share" "$CONF_DIR"
WORK="$(mktemp -d "$HOME/.local/share/.rcu-stage.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cp -R "$INSTALL_ROOT/bin" "$INSTALL_ROOT/lib" "$WORK/"
touch "$WORK/.rcu-managed"

# --- Atomic activation ---
# Keep the last working version for rollback.
if [[ -d "$PREFIX" ]]; then
  # Rename current → backup (same filesystem → atomic rename)
  local_backup="$PREFIX.backup.$(date +%Y%m%d%H%M%S)"
  mv -f "$PREFIX" "$local_backup" || fail "Cannot back up existing installation"
fi

# Move staging → prefix (same filesystem → atomic rename)
mv -f "$WORK" "$PREFIX" || {
  # Rollback: restore backup if it existed
  if [[ -n "${local_backup:-}" ]] && [[ -d "$local_backup" ]]; then
    mv -f "$local_backup" "$PREFIX"
  fi
  fail "Cannot activate new version; rolled back."
}
trap - EXIT

# --- Config (idempotent) ---
if [[ ! -f "$CONF_DIR/config" ]]; then
  cp "$INSTALL_ROOT/config/config.example" "$CONF_DIR/config"
  chmod 600 "$CONF_DIR/config"
fi

# --- Symlink (atomic on same filesystem) ---
if [[ ! -L "$LINK" ]]; then
  # Create temp link next to target, then rename
  local_tmp_link="$HOME/.local/bin/.rcu-link.XXXXXX"
  local_tmp_link="$(mktemp -u "$local_tmp_link")"
  ln -s "$PREFIX/bin/rcu" "$local_tmp_link"
  mv -f "$local_tmp_link" "$LINK" || { rm -f "$local_tmp_link"; fail "Cannot create symlink"; }
fi

# --- PATH in zshrc (idempotent, never use Zsh's 'path' special variable) ---
if [[ ! -f "$ZSHRC" ]] || ! grep -Fxq "$MARKER" "$ZSHRC"; then
  printf '\n%s\n%s\n' "$MARKER" 'export PATH="$HOME/.local/bin:$PATH"' >> "$ZSHRC"
fi

msg 'rcu installed. Open a new macOS terminal or run: source ~/.zshrc'
msg 'Commands: rcu utm start | connect | shell | stop | health | status'
msg 'Only real checks are counted as percentage milestones; not guest boot progress.'
