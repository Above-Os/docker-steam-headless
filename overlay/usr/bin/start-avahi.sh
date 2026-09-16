#!/usr/bin/env bash
###
# File: start-avahi.sh
#
# Two networking modes:
#   - No macvlan / no net1: olaresd answers mDNS and rewrites Sunshine's
#     advertised address to NODE_IP. Do not run avahi (it would fight olaresd).
#   - macvlan net1: olaresd does not proxy. Avahi must answer on net1 and
#     publish that underlay address.
#
# Avahi talks to a private system bus under /run/avahi-bus, never the host
# socket at /run/dbus (host policy rejects org.freedesktop.Avahi, and we
# must not register an Avahi name on the host bus).
###
set -e
source /usr/bin/common-functions.sh

AVAHI_BUS_DIR="/run/avahi-bus"
AVAHI_BUS="${AVAHI_BUS_DIR}/bus"
AVAHI_DBUS_CONF="/tmp/avahi-system-dbus.conf"
dbus_pid=""

_term() {
    kill -TERM "${dbus_pid}" 2>/dev/null || true
    pkill -TERM -x avahi-daemon 2>/dev/null || true
}
trap _term SIGTERM SIGINT

if ! has_net1_device; then
    echo "avahi: no net1 device; olaresd proxies mDNS, not starting"
    exec sleep infinity
fi

if ! wait_for_underlay_ip 15; then
    echo "avahi: net1 has no IPv4; olaresd still proxies mDNS, not starting"
    exec sleep infinity
fi

UNDERLAY_IP="$(ifconfig net1 2>/dev/null | grep -oP 'inet (addr:)?\K[\d\.]+' | head -n1)"
echo "avahi: macvlan mode, publishing on net1 (${UNDERLAY_IP:?})"

# Restrict publishing to the underlay NIC.
sed -i 's/^#\?allow-interfaces=.*/allow-interfaces=net1/' /etc/avahi/avahi-daemon.conf
sed -i 's/^#\?enable-dbus=.*/enable-dbus=yes/' /etc/avahi/avahi-daemon.conf
sed -i 's/^#\?publish-addresses=.*/publish-addresses=yes/' /etc/avahi/avahi-daemon.conf
sed -i 's/^#\?publish-workstation=.*/publish-workstation=no/' /etc/avahi/avahi-daemon.conf

mkdir -p "${AVAHI_BUS_DIR}" /run/avahi-daemon
chmod 755 "${AVAHI_BUS_DIR}" /run/avahi-daemon
rm -f "${AVAHI_BUS}"

cat > "${AVAHI_DBUS_CONF}" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <keep_umask/>
  <listen>unix:path=/run/avahi-bus/bus</listen>
  <policy context="default">
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow eavesdrop="true"/>
    <allow user="*"/>
  </policy>
</busconfig>
EOF

dbus-daemon --config-file="${AVAHI_DBUS_CONF}" --nofork --nopidfile &
dbus_pid=$!

for _ in $(seq 1 20); do
    [ -S "${AVAHI_BUS}" ] && break
    sleep 0.1
done
if [ ! -S "${AVAHI_BUS}" ]; then
    echo "avahi: FATAL: private dbus socket ${AVAHI_BUS} was not created"
    exit 1
fi
chmod 666 "${AVAHI_BUS}"

export_avahi_dbus
exec avahi-daemon --no-drop-root --no-chroot
