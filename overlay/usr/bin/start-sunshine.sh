#!/usr/bin/env bash
###
# File: start-sunshine.sh
# Project: bin
# File Created: Tuesday, 4th October 2022 8:22:17 pm
# Author: Josh.5 (jsunnex@gmail.com)
# -----
# Last Modified: Wednesday, 27th November 2024 3:54:19 pm
# Modified By: Josh5 (jsunnex@gmail.com)
###
set -e
source /usr/bin/common-functions.sh
unset LD_PRELOAD   # FIXME:

# CATCH TERM SIGNAL:
_term() {
    kill -INT "$sunshine_pid" 2>/dev/null
    sleep 0.5
    counter=0
    while kill -0 "$sunshine_pid"; do
        kill -TERM "$sunshine_pid" 2>/dev/null
        counter=$((counter + 1))
        [ "$counter" -gt 8 ] && break
        sleep 0.5
    done
    counter=0
    while kill -0 "$sunshine_pid"; do
        kill -KILL "$sunshine_pid" 2>/dev/null
        counter=$((counter + 1))
        [ "$counter" -gt 4 ] && break
        sleep 0.5
    done
}
trap _term SIGTERM SIGINT


# CONFIGURE:
# Install default configurations
mkdir -p "${USER_HOME:?}/.config/sunshine"
# FIXME:
if [ -f /etc/ld.so.preload ]; then
    cat /dev/null > ${USER_HOME:?}/.config/sunshine/so.preload && sudo mount --bind ${USER_HOME:?}/.config/sunshine/so.preload /etc/ld.so.preload
fi

EXTERNAL_IP="${NODE_IP:?}"
UNDERLAY_IP=$(ifconfig net1 2>/dev/null | grep -oP 'inet (addr:)?\K[\d\.]+' | head -n1)
if [ "X${UNDERLAY_IP}" != "X" ]; then
    EXTERNAL_IP="${UNDERLAY_IP:?}"
fi

if [ ! -f "${USER_HOME:?}/.config/sunshine/sunshine.conf" ]; then
    cp -vf /templates/sunshine/sunshine.conf "${USER_HOME:?}/.config/sunshine/sunshine.conf"
    echo "external_ip = ${EXTERNAL_IP}" >> "${USER_HOME:?}/.config/sunshine/sunshine.conf"
else
    sed -i "s/external_ip = .*/external_ip = ${EXTERNAL_IP}/" "${USER_HOME:?}/.config/sunshine/sunshine.conf"
fi
if [ ! -f "${USER_HOME:?}/.config/sunshine/apps.json" ]; then
    cp -vf /templates/sunshine/apps.json "${USER_HOME:?}/.config/sunshine/apps.json"
fi
if [ ! -f "${USER_HOME:?}/.config/sunshine/sunshine_state.json" ]; then
    echo "{}" > "${USER_HOME:?}/.config/sunshine/sunshine_state.json"
fi
# Reset the default username/password
if ([ "X${SUNSHINE_USER:-}" != "X" ] && [ "X${SUNSHINE_PASS:-}" != "X" ]); then
    /usr/bin/sunshine "${USER_HOME:?}/.config/sunshine/sunshine.conf" --creds "${SUNSHINE_USER:?}" "${SUNSHINE_PASS:?}"
fi
# If we are running the SHUI, then force the same user upon sunshine
if ([ "X${WEBUI_USER:-}" != "X" ] && [ "X${WEBUI_PASS:-}" != "X" ]); then
    /usr/bin/sunshine "${USER_HOME:?}/.config/sunshine/sunshine.conf" --creds "${WEBUI_USER:?}" "${WEBUI_PASS:?}"
fi
# Remove any auto-start scripts from user's .local dir
if [ -f "${USER_HOME:?}/.config/autostart/Sunshine.desktop" ]; then
    rm -fv "${USER_HOME:?}/.config/autostart/Sunshine.desktop"
fi


if ([ "${MODE}" != "s" ] && [ "${MODE}" != "secondary" ]); then
    # EXECUTE PROCESS:
    # Wait for the X server to start
    wait_for_x

    # Start a session bus instance of dbus-daemon
    wait_for_desktop_dbus_session
    export_desktop_dbus_session

    # Wait for the desktop to start
    wait_for_desktop
fi
# Wait for avahi-daemon only when macvlan net1 is the mDNS path.
# Without net1, olaresd proxies _nvstream._tcp and Sunshine advertises NODE_IP.
echo "wait for avahi-daemon"
wait_for_avahi

if [ "${ENABLE_SYSTEMD_UDEVD}" == "true" ]; then
    echo "wait for systemd-udevd"
    wait_for_udevd
fi

# Start the sunshine server
/usr/bin/dumb-init /usr/bin/sunshine "${USER_HOME:?}/.config/sunshine/sunshine.conf" &
sunshine_pid=$!


# WAIT FOR CHILD PROCESS:
wait "$sunshine_pid"
