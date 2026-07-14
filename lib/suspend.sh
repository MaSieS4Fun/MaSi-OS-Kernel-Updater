#!/usr/bin/env bash
# Userspace hooks for SM8550 deep suspend (systemd).
set -euo pipefail

install_deep_suspend_config() {
    [[ "${SUSPEND_DEEP:-0}" == "1" ]] || return 0
    [[ -d /etc/systemd ]] || {
        echo "  deep-suspend: no systemd — skip sleep.conf.d" >&2
        return 0
    }

    mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d

    install -m644 "${ROOT}/config/sleep/masi-deep-suspend.conf" \
        /etc/systemd/sleep.conf.d/masi-deep-suspend.conf
    install -m644 "${ROOT}/config/sleep/masi-logind-suspend.conf" \
        /etc/systemd/logind.conf.d/masi-suspend.conf

    systemctl daemon-reload 2>/dev/null || true
    echo "  deep-suspend: systemd sleep + logind (mem / power key)" >&2
}
