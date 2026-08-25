
print_header "Configure Avahi"

# Avahi is only the LAN mDNS responder when the underlay macvlan (net1) exists.
# Without net1, olaresd proxies GameStream mDNS and must remain the only
# process answering 224.0.0.251:5353 on the host.

if [ -d /sys/class/net/net1 ]; then
    print_step_header "net1 present: enable Avahi on underlay (olaresd is not proxying mDNS)"
    sed -i 's|^autostart.*=.*$|autostart=true|' /etc/supervisor.d/avahi.ini
    sed -i 's|^#\?allow-interfaces=.*|allow-interfaces=net1|' /etc/avahi/avahi-daemon.conf
    sed -i 's|^#\?enable-dbus=.*|enable-dbus=yes|' /etc/avahi/avahi-daemon.conf
else
    print_step_header "no net1: disable Avahi (olaresd proxies mDNS)"
    sed -i 's|^autostart.*=.*$|autostart=false|' /etc/supervisor.d/avahi.ini
fi

echo -e "\e[34mDONE\e[0m"
