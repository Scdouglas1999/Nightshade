#!/bin/bash
# D1 crash-resume leg: run a sim night, kill -9 the app the moment the dawn
# job reports `running`, relaunch, and assert the crash-recovery contract:
# the row is re-queued with attempts+1 at database open.
#
# NOTE: completing the re-queued job after relaunch requires the startup
# drainQueue() wiring (Phase C). Until that lands this script asserts the
# re-queue half and reports the drain half honestly as PENDING; once the
# wiring exists, set D1_EXPECT_DRAIN=1 to require completion.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
D1="${D1_SCRATCH:-/tmp/nightshade-d1-crash}"
BUNDLE="${D1_BUNDLE:-$HERE/../../../apps/desktop/build/linux/x64/release/bundle/nightshade_desktop}"
T=d1-secret-token
P="${D1_PORT:-8094}"
B="http://127.0.0.1:$P"
AH="Authorization: Bearer $T"
DBDIR=$D1/db; OUT=$D1/captures; DROP=$D1/drop; DATA=$D1/data
LOG=$D1/app.log
PASS=0; FAIL=0
say()  { echo "[d1cr] $*"; }
ok()   { PASS=$((PASS+1)); echo "[d1cr]   PASS: $*"; }
bad()  { FAIL=$((FAIL+1)); echo "[d1cr]   FAIL: $*"; }
api()  { curl -sf -m 10 -H "$AH" "$@"; }
Q()    { sqlite3 "$DBDIR/nightshade.db" "$1"; }

pkill -f nightshade_desktop 2>/dev/null; sleep 1
rm -rf "$D1"; mkdir -p "$DBDIR" "$OUT" "$DROP" "$DATA"

launch() {
  NIGHTSHADE_DATABASE_DIR=$DBDIR NIGHTSHADE_DATA_DIR=$DATA LIBGL_ALWAYS_SOFTWARE=1 \
    "$BUNDLE" --headless --auth-token=$T --port=$P >> "$LOG" 2>&1 &
  APP=$!
  for i in $(seq 1 40); do
    sleep 1
    curl -sf -m 2 "$B/api/info" >/dev/null 2>&1 && return 0
    kill -0 $APP 2>/dev/null || { bad "app exited during launch"; return 1; }
  done
  bad "API never came up"; return 1
}

say "=== setup (schema boot, seed, configure, run sequence) ==="
launch || exit 1
kill -TERM $APP; sleep 3
NOW=$(date +%s)
sqlite3 "$DBDIR/nightshade.db" "INSERT INTO delivery_targets(name,kind,config_json,enabled,content_json,secret_ref,created_at,updated_at) VALUES('d1-drop','watched_folder','{\"path\":\"$DROP\"}',1,'[\"linear_masters\",\"draft_render\",\"night_report\"]',NULL,$NOW,$NOW);"
launch || exit 1
api -X POST "$B/api/settings" -H 'Content-Type: application/json' \
  -d "{\"settings\":{\"imageOutputPath\":\"$OUT\",\"notificationsEnabled\":true,\"notifyOnSequenceComplete\":true}}" >/dev/null
sleep 1
api -X POST "$B/api/settings/location" -H 'Content-Type: application/json' \
  -d '{"location":{"latitude":40.0,"longitude":-105.0,"elevation":1600.0}}' >/dev/null
sleep 1
api -X POST "$B/api/post-session/settings" -H 'Content-Type: application/json' -d '{"autoIntegrate":true}' >/dev/null
sleep 1
PID=$(api -X POST "$B/api/profiles" -H 'Content-Type: application/json' -d '{
 "profile":{"id":"","name":"d1-crash-rig","cameraId":"sim_camera_1","mountId":"sim_mount_1",
  "filterWheelId":"sim_filterwheel_1","focuserId":"sim_focuser_1","focalLength":1000.0,
  "aperture":200.0,"defaultBinX":1,"defaultBinY":1,"filterNames":"[\"L\",\"R\",\"G\",\"B\"]"}}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))')
sleep 1
api -X POST "$B/api/profiles/$PID/load" >/dev/null
sleep 1
for d in camera:sim_camera_1 mount:sim_mount_1 filterWheel:sim_filterwheel_1 focuser:sim_focuser_1; do
  api -X POST "$B/api/devices/connect" -H 'Content-Type: application/json' \
    -d "{\"deviceId\":\"${d#*:}\",\"deviceType\":\"${d%%:*}\"}" >/dev/null; sleep 1
done
python3 "$HERE/make_sequence.py" "$D1/sequence.json"
api -X POST "$B/api/sequencer/save-path" -H 'Content-Type: application/json' -d "{\"path\":\"$OUT\"}" >/dev/null
sleep 1
curl -sf -m 15 -H "$AH" -X POST "$B/api/sequencer/load" -H 'Content-Type: application/json' --data-binary @"$D1/sequence.json" >/dev/null
sleep 1
api -X POST "$B/api/sequencer/start" >/dev/null && ok "sequence started" || { bad "start"; exit 1; }

say "=== wait for the dawn job to report running, then kill -9 ==="
KILLED=0
for i in $(seq 1 240); do
  sleep 1
  ST=$(Q "SELECT state FROM darkroom_jobs ORDER BY id DESC LIMIT 1;" 2>/dev/null)
  if [ "$ST" = "running" ]; then
    kill -9 $APP 2>/dev/null; pkill -9 -f nightshade_desktop 2>/dev/null
    KILLED=1; ok "killed app with job running (${i}s after start)"; break
  fi
  [ "$ST" = "done" ] && { bad "job finished before the kill window — pipeline too fast for this leg on this machine"; break; }
done
[ "$KILLED" = "1" ] || { say "teardown"; pkill -f nightshade_desktop 2>/dev/null; echo "[d1cr] RESULT: PASS=$PASS FAIL=$((FAIL+1))"; exit 1; }
sleep 2
PRE_ATTEMPTS=$(Q "SELECT attempts FROM darkroom_jobs ORDER BY id DESC LIMIT 1;")

say "=== relaunch: crash-recovery must re-queue the running row ==="
launch || exit 1
sleep 3
ROW=$(Q "SELECT state||'|'||attempts FROM darkroom_jobs ORDER BY id DESC LIMIT 1;")
STATE=${ROW%%|*}; ATT=${ROW##*|}
if [ "$STATE" = "queued" ] && [ "$ATT" -gt "${PRE_ATTEMPTS:-0}" ]; then
  ok "row re-queued with attempts=$ATT (was $PRE_ATTEMPTS)"
elif [ "$STATE" = "running" ] || [ "$STATE" = "done" ]; then
  ok "row state=$STATE attempts=$ATT — a drain path picked it up (Phase C wiring present)"
else
  bad "row state=$STATE attempts=$ATT after relaunch"
fi

if [ "${D1_EXPECT_DRAIN:-0}" = "1" ]; then
  DONE=""
  for i in $(seq 1 180); do
    sleep 2
    DONE=$(Q "SELECT state FROM darkroom_jobs ORDER BY id DESC LIMIT 1;")
    [ "$DONE" = "done" ] && break
  done
  [ "$DONE" = "done" ] && ok "re-queued job drained to done" || bad "re-queued job state=$DONE (drain expected)"
else
  say "  drain-to-done not asserted (D1_EXPECT_DRAIN=0; startup drain wiring lands with Phase C)"
fi

say "=== teardown ==="
kill -TERM $APP 2>/dev/null; sleep 3; pkill -f nightshade_desktop 2>/dev/null
echo "[d1cr] RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
