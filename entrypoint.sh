#!/usr/bin/env bash
# Starts the INDI server (or INDI Web Manager) and optionally PHD2.
# If any managed process exits, the container exits so Docker's restart policy recovers it.
set -euo pipefail

INDI_MODE="${INDI_MODE:-static}"
INDI_DRIVERS="${INDI_DRIVERS:-}"
INDI_VERBOSE="${INDI_VERBOSE:-false}"
ENABLE_PHD2="${ENABLE_PHD2:-true}"
INDI_AUTOCONNECT="${INDI_AUTOCONNECT:-true}"
INDI_AUTOCONNECT_TIMEOUT="${INDI_AUTOCONNECT_TIMEOUT:-300}"

INDI_PORT=7624
WEB_PORT=8624

log() { echo "[entrypoint] $*"; }
die() { log "ERROR: $*"; exit 1; }

pids=()
helper_pids=()   # background helpers; unlike pids, their exit doesn't stop the container
shutdown() {
    log "Shutting down..."
    kill -TERM "${pids[@]}" "${helper_pids[@]}" 2>/dev/null || true
    wait || true
    exit 0
}
trap shutdown SIGTERM SIGINT

# Connects every device indiserver exposes, so hardware is online at boot without a client.
# Each device is retried until it connects once (USB devices may still be enumerating, or
# be plugged in late); after that, connect/disconnect is left to Ekos.
autoconnect() {
    set +e
    local deadline=$((SECONDS + INDI_AUTOCONNECT_TIMEOUT)) line dev
    local -A seen=() connected=()
    sleep 3
    while (( SECONDS < deadline )); do
        while IFS= read -r line; do
            dev="${line%.CONNECTION.CONNECT=*}"
            seen[$dev]=1
            [[ -n "${connected[$dev]:-}" ]] && continue
            if [[ "$line" == *=On ]]; then
                connected[$dev]=1
                log "autoconnect: '$dev' connected"
            else
                indi_setprop -p "$INDI_PORT" "$dev.CONNECTION.CONNECT=On" >/dev/null 2>&1
            fi
        done < <(indi_getprop -p "$INDI_PORT" -t 2 '*.CONNECTION.CONNECT' 2>/dev/null)
        sleep 10
    done
    for dev in "${!seen[@]}"; do
        [[ -n "${connected[$dev]:-}" ]] || log "autoconnect: WARNING '$dev' did not connect within ${INDI_AUTOCONNECT_TIMEOUT}s (check cable/power, then connect from Ekos)"
    done
}

mkdir -p "$HOME/.indi"

case "$INDI_MODE" in
    static)
        [[ -n "$INDI_DRIVERS" ]] || die "INDI_MODE=static requires INDI_DRIVERS (e.g. 'indi_simulator_telescope indi_simulator_ccd')"
        for driver in $INDI_DRIVERS; do
            command -v "$driver" >/dev/null || die "driver '$driver' not found (list drivers with: make drivers)"
        done
        indiserver_args=(-p "$INDI_PORT")
        [[ "$INDI_VERBOSE" == "true" ]] && indiserver_args+=(-v)
        log "Starting indiserver on :$INDI_PORT with drivers: $INDI_DRIVERS"
        # shellcheck disable=SC2086  # INDI_DRIVERS is intentionally word-split
        indiserver "${indiserver_args[@]}" $INDI_DRIVERS &
        pids+=($!)
        if [[ "$INDI_AUTOCONNECT" == "true" ]]; then
            autoconnect &
            helper_pids+=($!)
        fi
        ;;
    webmanager)
        log "Starting INDI Web Manager on :$WEB_PORT (it launches indiserver on :$INDI_PORT from a profile)"
        indi-web --port "$WEB_PORT" --indi-port "$INDI_PORT" --conf "$HOME/.indi" &
        pids+=($!)
        ;;
    *)
        die "unknown INDI_MODE '$INDI_MODE' (expected 'static' or 'webmanager')"
        ;;
esac

if [[ "$ENABLE_PHD2" == "true" ]]; then
    command -v phd2 >/dev/null || die "ENABLE_PHD2=true but PHD2 is not installed (image built with INSTALL_PHD2=false)"

    # Locks survive container restarts; clear them or Xvfb/PHD2 refuse to start
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 "$HOME"/phd2.*

    log "Starting Xvfb on :99 for PHD2"
    Xvfb :99 -screen 0 1280x800x24 -nolisten tcp &
    pids+=($!)
    export DISPLAY=:99
    for _ in {1..50}; do [[ -e /tmp/.X11-unix/X99 ]] && break; sleep 0.1; done

    log "Starting PHD2 (event server on :4400)"
    phd2 &
    pids+=($!)
fi

log "Ready."

status=0
wait -n "${pids[@]}" || status=$?
log "A managed process exited (status $status); stopping container"
kill -TERM "${pids[@]}" "${helper_pids[@]}" 2>/dev/null || true
wait || true
exit $(( status == 0 ? 1 : status ))
