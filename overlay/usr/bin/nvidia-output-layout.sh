#!/usr/bin/env bash
###
# Keep the NVIDIA X screen on exactly one head.
#
# Olares One forces ConnectedMonitor "DFP-0, DFP-1" so headless capture still
# has an output. That makes both HDMI-0 and DP-0 look "connected" forever:
# xfsettingsd then enables both, the desktop overlaps, and sysfs status cannot
# be used to detect a physical HDMI plug.
#
# A real monitor publishes its EDID into RandR (preferred mode is native).
# An unplugged HDMI head falls back to NVIDIA's 1024x768 dummy preferred
# mode. Poll that, then enable HDMI or DP exclusively.
###
set -e
source /usr/bin/common-functions.sh

_term() {
    exit 0
}
trap _term SIGTERM SIGINT

POLL_INTERVAL="${NVIDIA_OUTPUT_LAYOUT_POLL:-2}"
DUMMY_PREFERRED="1024x768"

wait_for_x

xrandr_q() {
    xrandr -q 2>/dev/null || true
}

first_connected() {
    local prefix="${1:?}"
    xrandr_q | awk -v p="${prefix}" '$1 ~ ("^" p "-[0-9]+$") && $2 == "connected" { print $1; exit }'
}

preferred_mode() {
    local output="${1:?}"
    xrandr_q | awk -v o="${output}" '
        $1 == o { p=1; next }
        p && $0 ~ /^[^[:space:]]/ { exit }
        p && /\+/ { print $1; exit }
    '
}

highest_refresh() {
    local output="${1:?}"
    local mode="${2:?}"
    xrandr_q | awk -v o="${output}" -v m="${mode}" '
        $1 == o { p=1; next }
        p && $0 ~ /^[^[:space:]]/ { exit }
        p && $1 == m {
            for (i = 2; i <= NF; i++) {
                r = $i
                gsub(/[+*]/, "", r)
                if (r + 0 > best) best = r + 0
            }
        }
        END { if (best != "") printf "%.2f\n", best }
    '
}

output_is_active() {
    local output="${1:?}"
    xrandr_q | awk -v o="${output}" '
        $1 == o && $2 == "connected" {
            if ($3 == "primary" && $4 ~ /^[0-9]+x[0-9]+\+/) exit 0
            if ($3 ~ /^[0-9]+x[0-9]+\+/) exit 0
            exit 1
        }
        END { exit 1 }
    '
}

hdmi_has_real_monitor() {
    local output="${1:-}"
    local preferred
    [ -n "${output}" ] || return 1
    preferred="$(preferred_mode "${output}")"
    [ -n "${preferred}" ] || return 1
    [ "${preferred}" != "${DUMMY_PREFERRED}" ]
}

disable_xfce_auto_enable() {
    xfconf-query -c displays -p /AutoEnableProfiles -n -t int -s 0 >/dev/null 2>&1 || true
}

apply_hdmi() {
    local hdmi="${1:?}"
    local dp="${2:-}"
    local mode rate cmd
    mode="$(preferred_mode "${hdmi}")"
    [ -n "${mode}" ] || mode="--auto"
    cmd=(xrandr)
    if [ -n "${dp}" ]; then
        cmd+=(--output "${dp}" --off)
    fi
    if [ "${mode}" = "--auto" ]; then
        cmd+=(--output "${hdmi}" --primary --auto --pos 0x0)
    else
        rate="$(highest_refresh "${hdmi}" "${mode}")"
        cmd+=(--output "${hdmi}" --primary --mode "${mode}" --pos 0x0)
        if [ -n "${rate}" ]; then
            cmd+=(--rate "${rate}")
        fi
    fi
    echo "**** Enabling ${hdmi} (${mode}${rate:+ @ ${rate}Hz}), disabling ${dp:-none} ****"
    "${cmd[@]}"
}

apply_dp() {
    local hdmi="${1:-}"
    local dp="${2:?}"
    local cmd
    cmd=(xrandr)
    if [ -n "${hdmi}" ]; then
        cmd+=(--output "${hdmi}" --off)
    fi
    cmd+=(--output "${dp}" --primary --pos 0x0)
    if [ -n "${DISPLAY_SIZEW:-}" ] && [ -n "${DISPLAY_SIZEH:-}" ]; then
        if xrandr_q | awk -v o="${dp}" -v m="${DISPLAY_SIZEW}x${DISPLAY_SIZEH}" '
            $1 == o { p=1; next }
            p && $0 ~ /^[^[:space:]]/ { exit }
            p && $1 == m { found=1 }
            END { exit found ? 0 : 1 }
        '; then
            cmd+=(--mode "${DISPLAY_SIZEW}x${DISPLAY_SIZEH}")
            if [ -n "${DISPLAY_REFRESH:-}" ]; then
                cmd+=(--rate "${DISPLAY_REFRESH}")
            fi
        else
            cmd+=(--auto)
        fi
    else
        cmd+=(--auto)
    fi
    echo "**** Enabling ${dp} (headless), disabling ${hdmi:-none} ****"
    "${cmd[@]}"
}

layout_needed() {
    local hdmi="${1:-}"
    local dp="${2:-}"
    if hdmi_has_real_monitor "${hdmi}"; then
        output_is_active "${hdmi}" || return 0
        if [ -n "${dp}" ] && output_is_active "${dp}"; then
            return 0
        fi
        return 1
    fi
    if [ -z "${dp}" ]; then
        return 1
    fi
    output_is_active "${dp}" || return 0
    if [ -n "${hdmi}" ] && output_is_active "${hdmi}"; then
        return 0
    fi
    return 1
}

apply_layout() {
    local hdmi dp
    hdmi="$(first_connected HDMI)"
    dp="$(first_connected DP)"
    if [ -z "${hdmi}" ] && [ -z "${dp}" ]; then
        echo "**** No HDMI or DP outputs reported as connected ****"
        return 0
    fi
    disable_xfce_auto_enable
    if ! layout_needed "${hdmi}" "${dp}"; then
        return 0
    fi
    if hdmi_has_real_monitor "${hdmi}"; then
        apply_hdmi "${hdmi}" "${dp}"
    elif [ -n "${dp}" ]; then
        apply_dp "${hdmi}" "${dp}"
    fi
}

echo "**** Starting NVIDIA output layout helper ****"
apply_layout || true
while true; do
    sleep "${POLL_INTERVAL}"
    apply_layout || true
done
