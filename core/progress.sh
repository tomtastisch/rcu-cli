#!/bin/bash
# core/progress.sh — Terminal UI with gum integration.
# Provides status display, progress tracking, and error formatting.
# Percentages reflect only completed, verifiable check phases.

# Print a styled notice using gum if available and terminal is interactive
rcu_notice() {
    if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
        gum style --foreground 39 "$*"
    else
        printf '%s\n' "$*"
    fi
}

# Print an error message to stderr
rcu_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

# Print a check phase with percentage based on completed milestones
# Arguments: phase_number total_phases label
rcu_phase() {
    local n="$1"
    local total="$2"
    local label="$3"
    local pct=$(( (n * 100) / total ))
    printf '[%d/%d] %3d%%  %s\n' "$n" "$total" "$pct" "$label"
}

# Run a command with a spinning indicator if gum is available
rcu_spin() {
    local title="$1"
    shift
    if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        printf '%s... ' "$title"
        "$@"
    fi
}

# Display a status line with key and value
rcu_status_line() {
    local key="$1"
    local value="$2"
    printf '  %-20s %s\n' "$key:" "$value"
}

# Display a pass/fail status
rcu_status_pass() {
    local label="$1"
    if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
        gum style --foreground 2 "✓  $label"
    else
        printf '✓  %s\n' "$label"
    fi
}

rcu_status_fail() {
    local label="$1"
    if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
        gum style --foreground 1 "✗  $label"
    else
        printf '✗  %s\n' "$label"
    fi
}

rcu_status_unknown() {
    local label="$1"
    printf '?  %s\n' "$label"
}

# Print help text
rcu_show_help() {
    cat <<'EOF'
rcu — Remote Control Unit

Usage: rcu <command> [subcommand] [options]

UTM Commands:
  rcu utm start       Start VM and await verified SSH login
  rcu utm connect     Verify remote connection without opening a shell
  rcu utm shell       Open Debian terminal (exit returns to macOS)
  rcu utm stop        Ask guest to shut down safely; never force stop
  rcu utm health      Check UTM, networking and SSH authentication
  rcu utm status      Show UTM state and connection details

System Commands:
  rcu help            Show this help message
  rcu doctor          Diagnose installation and environment
  rcu update          Update to a new version (requires new bundle)
  rcu rollback        Roll back to previous verified version
  rcu uninstall       Remove RCU installation safely

Notes:
  Progress percentages represent verified checks, not actual kernel boot progress.
  UTM does not expose a validated numerical boot-progress metric.
  Configuration: ~/.config/rcu/config
  Bundle location: ~/.local/share/utm/rcu/
EOF
}
