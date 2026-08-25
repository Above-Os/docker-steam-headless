#!/usr/bin/env bash
###
# File: start-desktop.sh
# Project: bin
# File Created: Thursday, 1st January 1970 12:00:00 pm
# Author: Josh.5 (jsunnex@gmail.com)
# -----
# Last Modified: Sunday, 2nd October 2022 22:58:17 pm
# Modified By: Josh.5 (jsunnex@gmail.com)
###
set -e

# CATCH TERM SIGNAL:
_term() {
    kill -TERM "$pulseaudio_pid" 2>/dev/null
}
trap _term SIGTERM SIGINT

# k8s sets PULSE_SERVER=unix:/tmp/pulse/pulse-socket, but the daemon listens on
# $XDG_RUNTIME_DIR/pulse/native until we explicitly expose that extra socket.
# Using the env var here makes pactl fail, then this script kills PulseAudio.
unset PULSE_SERVER

# EXECUTE PROCESS:
echo "PULSEAUDIO: Starting pulseaudio service"
#/usr/bin/pulseaudio --disallow-module-loading --disallow-exit --exit-idle-time=-1 &
/usr/bin/pulseaudio --exit-idle-time=-1 &
pulseaudio_pid=$!


wait_for_pulse() {
    MAX=60 # About 30 seconds
    CT=0
    while ! pactl stat >/dev/null 2>&1; do
        sleep 0.50s
        CT=$(( CT + 1 ))
        if [ "$CT" -ge "$MAX" ]; then
            echo "FATAL: $0: Gave up waiting for pulse audio"
            kill -TERM "$pulseaudio_pid" 2>/dev/null
            exit 11
        fi
    done
}

wait_for_pulse

# Expose the socket path that Steam/container env expects (PULSE_SERVER).
if [ -n "${PULSE_SOCKET_DIR:-}" ]; then
    mkdir -p "${PULSE_SOCKET_DIR}"
    chmod 777 "${PULSE_SOCKET_DIR}"
    if [ ! -S "${PULSE_SOCKET_DIR}/pulse-socket" ]; then
        echo "PULSEAUDIO: Creating ${PULSE_SOCKET_DIR}/pulse-socket"
        pactl load-module module-native-protocol-unix \
            socket="${PULSE_SOCKET_DIR}/pulse-socket" auth-anonymous=1 \
            || echo "PULSEAUDIO: WARNING: failed to create ${PULSE_SOCKET_DIR}/pulse-socket"
    fi
fi

if [[ "${DEVICE_NAME}" = "Olares One" ]]; then
    echo "PULSEAUDIO: Setting Olares One HDMI audio output"
    # Set HDMI audio output
    if pactl load-module module-alsa-sink device=plughw:0,3 sink_name=nvhdmi; then
        pactl set-default-sink nvhdmi || true
        amixer -c 0 sset 'IEC958' on || true
    else
        echo "PULSEAUDIO: WARNING: failed to load HDMI sink plughw:0,3"
    fi
fi

# WAIT FOR CHILD PROCESS:
wait "$pulseaudio_pid"
