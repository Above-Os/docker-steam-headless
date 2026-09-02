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

# An enabled output carries a "<mode>+<x>+<y>" geometry, either right after
# "connected" or after "primary". Keep the exit status in END: an exit inside a
# rule jumps to END, so an "exit 1" there would mask a successful match.
output_is_active() {
    local output="${1:?}"
    xrandr_q | awk -v o="${output}" '
        $1 == o && $2 == "connected" {
            if ($3 ~ /^[0-9]+x[0-9]+\+/ || $4 ~ /^[0-9]+x[0-9]+\+/) active = 1
            exit
        }
        END { exit active ? 0 : 1 }
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

has_mode() {
    local output="${1:?}"
    local mode="${2:?}"
    xrandr_q | awk -v o="${output}" -v m="${mode}" '
        $1 == o { p=1; next }
        p && $0 ~ /^[^[:space:]]/ { exit }
        p && $1 == m { found=1 }
        END { exit found ? 0 : 1 }
    '
}

# Mode to use when a head is switched on. A head that is already on keeps
# whatever mode it has: Sunshine and the user own the resolution once the
# desktop is up, and re-asserting a default here would undo their changes.
enable_args() {
    local output="${1:?}"
    local role="${2:?}"
    local mode rate
    if [ "${role}" = "hdmi" ]; then
        mode="$(preferred_mode "${output}")"
        if [ -n "${mode}" ]; then
            rate="$(highest_refresh "${output}" "${mode}")"
        fi
    elif [ -n "${DISPLAY_SIZEW:-}" ] && [ -n "${DISPLAY_SIZEH:-}" ] \
        && has_mode "${output}" "${DISPLAY_SIZEW}x${DISPLAY_SIZEH}"; then
        mode="${DISPLAY_SIZEW}x${DISPLAY_SIZEH}"
        rate="${DISPLAY_REFRESH:-}"
    fi
    if [ -z "${mode}" ]; then
        printf '%s' "--auto"
        return 0
    fi
    printf '%s' "--mode ${mode}"
    if [ -n "${rate}" ]; then
        printf '%s' " --rate ${rate}"
    fi
}

apply_layout() {
    local hdmi dp want unwanted role cmd mode_args
    hdmi="$(first_connected HDMI)"
    dp="$(first_connected DP)"
    if [ -z "${hdmi}" ] && [ -z "${dp}" ]; then
        return 0
    fi
    disable_xfce_auto_enable

    if hdmi_has_real_monitor "${hdmi}"; then
        want="${hdmi}"
        unwanted="${dp}"
        role="hdmi"
    else
        want="${dp}"
        unwanted="${hdmi}"
        role="dp"
    fi
    [ -n "${want}" ] || return 0

    cmd=(xrandr)
    if [ -n "${unwanted}" ] && output_is_active "${unwanted}"; then
        cmd+=(--output "${unwanted}" --off)
    fi
    if output_is_active "${want}"; then
        # Nothing to switch on, so only step in when the wrong head is lit.
        [ "${#cmd[@]}" -gt 1 ] || return 0
    else
        cmd+=(--output "${want}" --primary --pos 0x0)
        read -r -a mode_args <<< "$(enable_args "${want}" "${role}")"
        cmd+=("${mode_args[@]}")
    fi

    echo "**** Applying layout: ${cmd[*]:1} ****"
    "${cmd[@]}"
}

echo "**** Starting NVIDIA output layout helper ****"
apply_layout || true
while true; do
    sleep "${POLL_INTERVAL}"
    apply_layout || true
done
