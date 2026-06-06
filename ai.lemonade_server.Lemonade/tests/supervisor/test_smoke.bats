#!/usr/bin/env bats
#
# Smoke test for lemonade-supervisor.sh. The supervisor calls /app/bin/{lemond,
# lemonade-tray,lemonade-app} by absolute path, so the mocks are dropped there —
# which is why this runs in the throwaway bats container (make test).

wait_file()   { for _ in {1..50}; do [ -f "$1" ] && return 0; sleep 0.1; done; return 1; }
wait_gone()   { for _ in {1..50}; do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done; return 1; }
wait_health() { for _ in {1..50}; do curl -sf --max-time 0.2 "$1" >/dev/null 2>&1 && return 0; sleep 0.1; done; return 1; }

setup() {
    TMPROOT="$(mktemp -d)"
    export XDG_RUNTIME_DIR="$TMPROOT/run"
    export FLATPAK_ID="ai.lemonade_server.Lemonade"
    export LEMONADE_DATA_DIR="$TMPROOT/data"
    mkdir -p "$TMPROOT/run" "$TMPROOT/data" /app/bin
    unset LEMONADE_FLATPAK_FORCE_BUNDLED LEMONADE_HOST LEMONADE_PORT
    SUPERVISOR="$BATS_TEST_DIRNAME/../../lemonade-supervisor.sh"

    # Mock lemond: record argv, then serve /api/v1/health (200) and
    # POST /internal/shutdown (write a marker, exit). exec keeps the HTTP
    # server as the supervisor's tracked child.
    cat > /app/bin/lemond <<EOF
#!/usr/bin/env bash
echo "\$@" > "$TMPROOT/lemond.argv"
PORT=13305; [[ "\$*" =~ --port\ ([0-9]+) ]] && PORT="\${BASH_REMATCH[1]}"
exec python3 -c "
import http.server, os
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200 if self.path == '/api/v1/health' else 404); self.end_headers()
    def do_POST(self):
        if self.path == '/internal/shutdown':
            open('$TMPROOT/lemond.shutdown', 'w').close()
            self.send_response(200); self.end_headers(); os._exit(0)
        self.send_response(404); self.end_headers()
http.server.HTTPServer(('127.0.0.1', int('\$PORT')), H).serve_forever()
"
EOF

    # Mock tray + app: record a PID, stay up until killed.
    cat > /app/bin/lemonade-tray <<EOF
#!/usr/bin/env bash
echo \$\$ > "$TMPROOT/tray.pid"
exec sleep 100
EOF
    cat > /app/bin/lemonade-app <<EOF
#!/usr/bin/env bash
echo "\$@" > "$TMPROOT/app.argv"
echo \$\$ > "$TMPROOT/app.pid"
exec sleep 100
EOF

    chmod +x /app/bin/lemond /app/bin/lemonade-tray /app/bin/lemonade-app
}

teardown() {
    pkill -f "$TMPROOT" 2>/dev/null || true
    rm -rf "$TMPROOT"
}

@test "starts the bundled lemond when none is reachable" {
    export LEMONADE_PORT=13390
    timeout 15 "$SUPERVISOR" >/dev/null &
    SUP=$!
    wait_file "$TMPROOT/lemond.argv"
    wait_file "$TMPROOT/tray.pid"
    wait_file "$TMPROOT/app.pid"
    grep -q -- "--port 13390" "$TMPROOT/lemond.argv"
    kill "$SUP" 2>/dev/null || true
    wait "$SUP" 2>/dev/null || true
}

@test "connects to an external lemond and never shuts it down" {
    export LEMONADE_PORT=13391
    /app/bin/lemond --port 13391 &
    EXT=$!
    wait_health http://127.0.0.1:13391/api/v1/health
    rm -f "$TMPROOT/lemond.argv" "$TMPROOT/lemond.shutdown"

    timeout 15 "$SUPERVISOR" >/dev/null &
    SUP=$!
    wait_file "$TMPROOT/tray.pid"
    wait_file "$TMPROOT/app.pid"
    [ ! -f "$TMPROOT/lemond.argv" ]                 # supervisor started no lemond of its own
    app_pid="$(cat "$TMPROOT/app.pid")"

    sleep 2                                          # past the supervisor's ~1s tray-init grace
    kill -TERM "$(cat "$TMPROOT/tray.pid")"
    wait_gone "$app_pid"
    [ ! -f "$TMPROOT/lemond.shutdown" ]             # external lemond never told to shut down
    curl -sf --max-time 0.2 http://127.0.0.1:13391/api/v1/health >/dev/null
    kill -KILL "$EXT" 2>/dev/null || true
    wait "$SUP" 2>/dev/null || true
}

@test "quitting the tray shuts down a lemond the supervisor started" {
    export LEMONADE_PORT=13392
    timeout 15 "$SUPERVISOR" >/dev/null &
    SUP=$!
    wait_file "$TMPROOT/tray.pid"
    wait_file "$TMPROOT/app.pid"
    wait_file "$TMPROOT/lemond.argv"
    app_pid="$(cat "$TMPROOT/app.pid")"

    sleep 2                                          # past the supervisor's ~1s tray-init grace
    kill -TERM "$(cat "$TMPROOT/tray.pid")"
    wait_file "$TMPROOT/lemond.shutdown"
    wait_gone "$app_pid"
    wait "$SUP" 2>/dev/null || true
}

@test "no tray host: falls back to app-anchored, app close shuts down lemond" {
    printf '#!/usr/bin/env bash\nexit 1\n' > /app/bin/lemonade-tray
    export LEMONADE_PORT=13393
    timeout 15 "$SUPERVISOR" >/dev/null &
    SUP=$!
    wait_file "$TMPROOT/app.pid"
    [ ! -f "$TMPROOT/tray.pid" ]

    kill -TERM "$(cat "$TMPROOT/app.pid")"
    wait_file "$TMPROOT/lemond.shutdown"
    wait "$SUP" 2>/dev/null || true
}
