#!/usr/bin/env bash
###
# File: fix-wukong-frame-gen.sh
# Project: docker-steam-headless
# Enable NVIDIA DLSS Frame Generation for Black Myth: Wukong (AppID 2358720)
# under Proton. Run manually after a new install or game update.
#
# Usage (inside the container, game fully quit):
#   fix-wukong-frame-gen.sh
#
# What it does:
#   1. Set Dx12=1 and Dlss=1 in GameUserSettings.ini
#   2. Write HKLM\...\GraphicsDrivers HwSchMode=2 (un-greys the FG option)
#   3. On RTX 50 / Blackwell, replace nvngx_dlssg.dll with the NVIDIA Wine copy
###
set -euo pipefail

APPID="${WUKONG_APPID:-2358720}"
GAME_DIR_NAME="${WUKONG_DIR_NAME:-BlackMythWukong}"
STEAM_USER="${STEAM_USER:-default}"

log() { printf '%s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    if id "${STEAM_USER}" >/dev/null 2>&1; then
        log "Re-exec as ${STEAM_USER} (wine/prefix must be owned by the Steam user)"
        if command -v runuser >/dev/null 2>&1; then
            exec runuser -u "${STEAM_USER}" -- "$0" "$@"
        fi
        exec su -s /bin/bash "${STEAM_USER}" -c 'exec "$0" "$@"' -- "$0" "$@"
    fi
    die "Run as the Steam user (usually ${STEAM_USER}), not root"
fi

export HOME="${HOME:-/home/${STEAM_USER}}"

if pgrep -f 'b1-Win64-Shipping\.exe|BlackMythWukong/b1\.exe' >/dev/null 2>&1; then
    die "Game is running. Quit Black Myth: Wukong from Steam, then re-run this script."
fi

collect_steam_roots() {
    local -a seeds=(
        "${HOME}/.steam/steam"
        "${HOME}/.steam/root"
        "${HOME}/.local/share/Steam"
        "/mnt/games/GameLibrary/Steam"
    )
    local -a roots=()
    local seed vdf path
    for seed in "${seeds[@]}"; do
        [ -d "${seed}/steamapps" ] || continue
        roots+=("${seed}")
        vdf="${seed}/steamapps/libraryfolders.vdf"
        [ -f "${vdf}" ] || vdf="${seed}/config/libraryfolders.vdf"
        [ -f "${vdf}" ] || continue
        while IFS= read -r path; do
            [ -n "${path}" ] || continue
            [ -d "${path}/steamapps" ] || continue
            roots+=("${path}")
        done < <(python3 - "${vdf}" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="surrogateescape")
for m in re.finditer(r'"path"\s+"([^"]+)"', text):
    print(m.group(1).replace("\\\\", "/"))
PY
        )
    done
    printf '%s\n' "${roots[@]}" | awk 'NF && !seen[$0]++'
}

find_game_dir() {
    local root
    while IFS= read -r root; do
        if [ -x "${root}/steamapps/common/${GAME_DIR_NAME}/b1.exe" ] \
            || [ -d "${root}/steamapps/common/${GAME_DIR_NAME}/b1" ]; then
            printf '%s\n' "${root}/steamapps/common/${GAME_DIR_NAME}"
            return 0
        fi
    done
    return 1
}

find_prefix() {
    local root
    while IFS= read -r root; do
        if [ -d "${root}/steamapps/compatdata/${APPID}/pfx" ]; then
            printf '%s\n' "${root}/steamapps/compatdata/${APPID}/pfx"
            return 0
        fi
    done
    return 1
}

find_proton_wine() {
    local root wine
    while IFS= read -r root; do
        for wine in \
            "${root}/steamapps/common/Proton - Experimental/files/bin/wine" \
            "${root}/steamapps/common/Proton Hotfix/files/bin/wine" \
            "${root}/steamapps/common/Proton 9.0 (Beta)/files/bin/wine"
        do
            [ -x "${wine}" ] && { printf '%s\n' "${wine}"; return 0; }
        done
        wine="$(find "${root}/steamapps/common" "${root}/compatibilitytools.d" \
            "${HOME}/.steam/root/compatibilitytools.d" \
            -path '*/files/bin/wine' -type f 2>/dev/null | head -n 1 || true)"
        [ -n "${wine}" ] && [ -x "${wine}" ] && { printf '%s\n' "${wine}"; return 0; }
    done
    return 1
}

find_driver_dlssg() {
    local cand
    for cand in \
        /usr/lib/x86_64-linux-gnu/nvidia/wine/nvngx_dlssg.dll \
        /usr/lib/nvidia/wine/nvngx_dlssg.dll \
        /usr/lib64/nvidia/wine/nvngx_dlssg.dll
    do
        [ -f "${cand}" ] && { printf '%s\n' "${cand}"; return 0; }
    done
    cand="$(find /usr/lib /usr/lib64 -path '*/nvidia/wine/nvngx_dlssg.dll' -type f 2>/dev/null | head -n 1 || true)"
    [ -n "${cand}" ] && [ -f "${cand}" ] && { printf '%s\n' "${cand}"; return 0; }
    return 1
}

STEAM_ROOTS="$(collect_steam_roots)"
[ -n "${STEAM_ROOTS}" ] || die "No Steam library found under ${HOME} or /mnt/games"

GAME_DIR="$(printf '%s\n' "${STEAM_ROOTS}" | find_game_dir)" \
    || die "Black Myth: Wukong is not installed (missing steamapps/common/${GAME_DIR_NAME})"

PREFIX="$(printf '%s\n' "${STEAM_ROOTS}" | find_prefix)" \
    || die "Proton prefix not found: steamapps/compatdata/${APPID}/pfx (launch the game once, quit, then re-run)"

INI="${PREFIX}/drive_c/users/steamuser/AppData/Local/b1/Saved/Config/Windows/GameUserSettings.ini"
SYSTEM_REG="${PREFIX}/system.reg"
DLSSG_DST="${GAME_DIR}/Engine/Plugins/Runtime/Nvidia/Streamline/Binaries/ThirdParty/Win64/nvngx_dlssg.dll"
DLSSG_PFX="${PREFIX}/drive_c/windows/system32/nvngx_dlssg.dll"

log "Game:   ${GAME_DIR}"
log "Prefix: ${PREFIX}"

[ -f "${INI}" ] || die "GameUserSettings.ini not found. Launch the game once, quit fully, then re-run.
  expected: ${INI}"

python3 - "${INI}" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")

def set_key(blob: str, key: str, value: str) -> str:
    pat = re.compile(r'\("%s",\s*"[^"]*"\)' % re.escape(key))
    if pat.search(blob):
        return pat.sub('("%s", "%s")' % (key, value), blob, count=1)
    marker = "UISettingData=("
    idx = blob.find(marker)
    if idx == -1:
        raise SystemExit("UISettingData not found in GameUserSettings.ini")
    insert_at = idx + len(marker)
    return blob[:insert_at] + '("%s", "%s"),' % (key, value) + blob[insert_at:]

text = set_key(text, "Dx12", "1")
text = set_key(text, "Dlss", "1")
path.write_text(text, encoding="utf-8", errors="surrogateescape")

def get_key(blob: str, key: str) -> str:
    m = re.search(r'\("%s",\s*"([^"]*)"\)' % re.escape(key), blob)
    return m.group(1) if m else "?"

out = path.read_text(encoding="utf-8", errors="surrogateescape")
print("Dx12=%s Dlss=%s InsertFrame=%s" % (get_key(out, "Dx12"), get_key(out, "Dlss"), get_key(out, "InsertFrame")))
PY
ok "GameUserSettings.ini: Dx12=1, Dlss=1"

[ -f "${SYSTEM_REG}" ] || die "Missing ${SYSTEM_REG}"

python3 - "${SYSTEM_REG}" <<'PY'
import re, time, sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="surrogateescape")
key = "[System\\\\CurrentControlSet\\\\Control\\\\GraphicsDrivers]"
value = '"HwSchMode"=dword:00000002'

if re.search(r'"HwSchMode"=dword:', text):
    text, n = re.subn(r'"HwSchMode"=dword:[0-9A-Fa-f]+', value.split("=", 1)[0] + "=dword:00000002", text, count=1)
    if n == 0:
        raise SystemExit("failed to update existing HwSchMode")
else:
    ts = int(time.time())
    if not text.endswith("\n"):
        text += "\n"
    text += "\n%s %s\n%s\n" % (key, ts, value)

path.write_text(text, encoding="utf-8", errors="surrogateescape")
print("HwSchMode=2")
PY
ok "Wrote registry HwSchMode=2 into system.reg"

WINE_BIN=""
if WINE_BIN="$(printf '%s\n' "${STEAM_ROOTS}" | find_proton_wine)"; then
    export WINEPREFIX="${PREFIX}"
    export WINEDEBUG=-all
    export PATH="$(dirname "${WINE_BIN}"):${PATH:-/usr/bin}"
    if wine reg add 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' \
        /v HwSchMode /t REG_DWORD /d 2 /f >/tmp/wukong-hwsch.log 2>&1; then
        ok "wine reg add HwSchMode=2 (${WINE_BIN})"
    else
        warn "wine reg add failed (system.reg already patched). See /tmp/wukong-hwsch.log"
    fi
else
    warn "Proton wine not found; skipped wine reg add (system.reg already patched)"
fi

# if SRC="$(find_driver_dlssg)"; then
#     mkdir -p "$(dirname "${DLSSG_DST}")" "$(dirname "${DLSSG_PFX}")"
#     if [ -f "${DLSSG_DST}" ] && [ ! -f "${DLSSG_DST}.orig" ]; then
#         cp -a "${DLSSG_DST}" "${DLSSG_DST}.orig"
#         ok "Backed up game nvngx_dlssg.dll -> ${DLSSG_DST}.orig"
#     elif [ -f "${DLSSG_DST}" ]; then
#         ts="$(date +%Y%m%d%H%M%S)"
#         cp -a "${DLSSG_DST}" "${DLSSG_DST}.bak.${ts}"
#         ok "Backed up game nvngx_dlssg.dll -> ${DLSSG_DST}.bak.${ts}"
#     fi
#     cp -a "${SRC}" "${DLSSG_DST}"
#     cp -a "${SRC}" "${DLSSG_PFX}"
#     chmod 755 "${DLSSG_DST}" "${DLSSG_PFX}" 2>/dev/null || true
#     ok "Installed driver nvngx_dlssg.dll ($(basename "${SRC}")) into game + prefix"
# else
#     warn "NVIDIA Wine nvngx_dlssg.dll not found. RTX 40 may still work; RTX 50 usually needs it under /usr/lib/*/nvidia/wine/"
# fi

log ""
ok "Done. Launch Black Myth: Wukong and enable Frame Generation in the graphics menu."
log "Do not rely on Steam launch options (-dx12); they are often wiped by the client."
