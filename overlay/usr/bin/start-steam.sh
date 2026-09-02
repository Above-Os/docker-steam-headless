#!/usr/bin/env bash
###
# File: start-steam.sh
# Project: bin
# Drop stale Chromium singleton files before launching Steam.
# htmlcache lives on the persistent home volume; after a pod recreate the
# SingletonLock still names the previous hostname, and steamwebhelper then
# refuses the profile ("in use ... on another computer").
###
set -e

htmlcache="${HOME}/.steam/steam/config/htmlcache"
if [ -d "${htmlcache}" ]; then
    echo "STEAM: clearing stale CEF singleton files in ${htmlcache}"
    rm -f \
        "${htmlcache}/SingletonLock" \
        "${htmlcache}/SingletonCookie" \
        "${htmlcache}/SingletonSocket"
fi

exec /usr/games/steam "$@"
