#!/usr/bin/env bash
###
# File: start-x11vnc.sh
# Project: bin
# File Created: Tuesday, 6th October 2022 9:30:00 pm
# Author: Josh.5 (jsunnex@gmail.com)
# -----
# Last Modified: Tuesday, 6th October 2022 9:30:00 pm
# Modified By: Josh.5 (jsunnex@gmail.com)
###
set -e
source /usr/bin/common-functions.sh

# CATCH TERM SIGNAL:
_term() {
    kill -TERM "$x11vnc_pid" 2>/dev/null
}
trap _term SIGTERM SIGINT


# EXECUTE PROCESS:
# Wait for the X server to start
wait_for_x
# Start the x11vnc server
EXTRA_ARGS="${VNC_EXTRA_ARGS:-}"
if ([ "${MODE}" == "s" ] || [ "${MODE}" == "secondary" ]); then
    EXTRA_ARGS="${EXTRA_ARGS} -auth /home/default/.Xauthority -noshm "
fi

/usr/bin/x11vnc -display ${DISPLAY} -rfbport ${PORT_VNC} -shared -forever ${EXTRA_ARGS} &
x11vnc_pid=$!


# WAIT FOR CHILD PROCESS:
wait "$x11vnc_pid"
