#!/bin/bash
# commands/doctor.sh — Diagnose RCU installation and environment.
# No side effects. Read-only checks only.
# Requires: core/progress.sh

cmd_doctor() {
    local issues=0

    rcu_notice '=== RCU Doctor ==='
    rcu_notice ''

    # 1. Installation manifest
    rcu_notice '--- Installation ---'
    local bundle_dir="$HOME/.local/share/utm/rcu"
    local current_link="$bundle_dir/current"
    local launcher="$HOME/.local/bin/rcu"

    if [[ -L "$current_link" ]]; then
        local current_target
        current_target=$(readlink "$current_link")
        local current_version
        current_version=$(basename "$current_target")
        rcu_status_pass "Bundle current: v$current_version"
        if [[ -f "$current_target/install-manifest" ]]; then
            rcu_status_pass "Install manifest present"
        else
            rcu_status_fail "Install manifest missing"
            issues=$((issues + 1))
        fi
    else
        rcu_status_fail "Bundle symlink missing: $current_link"
        issues=$((issues + 1))
    fi

    # 2. Module resolution
    rcu_notice ''
    rcu_notice '--- Module Resolution ---'
    if [[ -L "$current_link" ]] && [[ -d "$(readlink "$current_link")" ]]; then
        local bundle_root
        bundle_root=$(readlink "$current_link")
        for f in bin/rcu core/config.sh core/utm.sh core/ssh.sh core/progress.sh \
                 commands/start.sh commands/connect.sh commands/shell.sh \
                 commands/stop.sh commands/health.sh commands/status.sh; do
            if [[ -f "$bundle_root/$f" ]]; then
                rcu_status_pass "$f"
            else
                rcu_status_fail "$f (missing)"
                issues=$((issues + 1))
            fi
        done
    else
        rcu_status_fail "Cannot resolve bundle — modules unchecked"
        issues=$((issues + 1))
    fi

    # 3. Launcher
    rcu_notice ''
    rcu_notice '--- Launcher ---'
    if [[ -f "$launcher" ]]; then
        if [[ -x "$launcher" ]]; then
            rcu_status_pass "Launcher exists and is executable"
        else
            rcu_status_fail "Launcher exists but is not executable"
            issues=$((issues + 1))
        fi
    else
        rcu_status_fail "Launcher missing: $launcher"
        issues=$((issues + 1))
    fi

    # 4. PATH integration
    rcu_notice ''
    rcu_notice '--- PATH Integration ---'
    if printf '%s\n' "${PATH//:/\n}" | grep -qF "$HOME/.local/bin"; then
        rcu_status_pass "$HOME/.local/bin in current PATH"
    else
        rcu_status_fail "$HOME/.local/bin NOT in current PATH"
        rcu_notice '  Fix: source ~/.zshrc  (or open a new terminal)'
        issues=$((issues + 1))
    fi

    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]] && grep -qF '# rcu-cli: managed PATH' "$zshrc" 2>/dev/null; then
        rcu_status_pass "Managed PATH entry in ~/.zshrc"
    else
        rcu_status_fail "No managed PATH entry in ~/.zshrc"
        issues=$((issues + 1))
    fi

    # 5. Dependencies
    rcu_notice ''
    rcu_notice '--- Dependencies ---'

    # Homebrew
    if command -v brew >/dev/null 2>&1; then
        rcu_status_pass "Homebrew: $(brew --version 2>&1 | head -1)"
    else
        rcu_status_fail "Homebrew: not found"
        issues=$((issues + 1))
    fi

    # gum
    if command -v gum >/dev/null 2>&1; then
        rcu_status_pass "gum: $(gum --version 2>&1)"
    else
        rcu_status_fail "gum: not found"
        issues=$((issues + 1))
    fi

    # UTM
    if [[ -d /Applications/UTM.app && -x /Applications/UTM.app/Contents/MacOS/utmctl ]]; then
        local utm_ver
        utm_ver=$(/Applications/UTM.app/Contents/MacOS/utmctl version 2>/dev/null || echo 'unknown')
        rcu_status_pass "UTM: v$utm_ver"
    else
        rcu_status_fail "UTM: not found"
        issues=$((issues + 1))
    fi

    # SSH
    if [[ -x /usr/bin/ssh ]]; then
        rcu_status_pass "SSH: $(/usr/bin/ssh -V 2>&1)"
    else
        rcu_status_fail "SSH: not found"
        issues=$((issues + 1))
    fi

    # 6. Configuration
    rcu_notice ''
    rcu_notice '--- Configuration ---'
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/rcu/config"
    if [[ -f "$conf" ]]; then
        rcu_status_pass "Config: $conf"
        if [[ -r "$conf" ]]; then
            rcu_status_pass "Config readable"
        else
            rcu_status_fail "Config not readable"
            issues=$((issues + 1))
        fi
        if [[ -L "$conf" ]]; then
            rcu_status_fail "Config is a symlink (unsafe)"
            issues=$((issues + 1))
        else
            rcu_status_pass "Config is a regular file"
        fi
    else
        rcu_status_unknown "Config: $conf (not yet created — will be created on first install)"
    fi

    # 7. Permissions
    rcu_notice ''
    rcu_notice '--- Permissions ---'
    if [[ -d "$bundle_dir" ]]; then
        local owner
        owner=$(stat -f '%Su' "$bundle_dir" 2>/dev/null || echo 'unknown')
        local my_user
        my_user=$(whoami)
        if [[ "$owner" == "$my_user" ]]; then
            rcu_status_pass "Bundle owned by $my_user"
        else
            rcu_status_fail "Bundle owned by $owner (expected $my_user)"
            issues=$((issues + 1))
        fi
    fi

    # Summary
    rcu_notice ''
    if [[ $issues -eq 0 ]]; then
        rcu_notice '=== Doctor: All checks passed ==='
        return 0
    else
        rcu_notice "=== Doctor: $issues issue(s) found ==="
        return 1
    fi
}
