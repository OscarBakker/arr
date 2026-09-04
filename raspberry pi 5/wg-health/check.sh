#!/bin/sh
# Snapshot WireGuard + Pi reachability. Always appends a local log.
# POSTs the same snapshot to Healthchecks.io so you can read it from
# a phone when you cannot get onto the LAN.
set -eu

LOGDIR="${LOGDIR:-/var/log/wg-health}"
WG_CONTAINER="${WG_CONTAINER:-wg-easy}"
SIGNAL_API_URL="${SIGNAL_API_URL:-http://127.0.0.1:8090}"
STAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

mkdir -p "$LOGDIR"

ok=1
reasons=""

append_reason() {
  reasons="${reasons}  - $1\n"
  ok=0
}

container_state="not found"
wg_out="(skipped)"
if docker inspect "$WG_CONTAINER" >/dev/null 2>&1; then
  container_state=$(docker inspect -f 'status={{.State.Status}} running={{.State.Running}} started={{.State.StartedAt}} restarts={{.RestartCount}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' "$WG_CONTAINER")
  running=$(docker inspect -f '{{.State.Running}}' "$WG_CONTAINER")
  if [ "$running" != "true" ]; then
    append_reason "wg-easy container is not running ($container_state)"
  else
    if wg_out=$(docker exec "$WG_CONTAINER" wg show 2>&1); then
      if ! printf '%s\n' "$wg_out" | grep -q '^interface:'; then
        append_reason "wg show returned no interface (WireGuard is not up inside the container)"
      fi
    else
      append_reason "wg show failed: $wg_out"
      wg_out="(failed)"
    fi
  fi
else
  running="false"
  append_reason "wg-easy container not found (stack not deployed, or different container name)"
fi

pubip=$(curl -fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null \
  || curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null \
  || echo "unreachable")

ipfile="$LOGDIR/last-public-ip"
lastip=""
ip_note="none"
if [ -f "$ipfile" ]; then
  lastip=$(cat "$ipfile")
fi
if [ "$pubip" = "unreachable" ]; then
  ip_note="Pi has no outbound internet (or IP lookup blocked)"
elif [ -n "$lastip" ] && [ "$pubip" != "$lastip" ]; then
  ip_note="public IP changed: ${lastip} -> ${pubip} (router/DDNS/port-forward may now be wrong)"
fi
if [ "$pubip" != "unreachable" ]; then
  printf '%s\n' "$pubip" > "$ipfile"
fi

host_uptime="unknown"
if [ -r /host/uptime ]; then
  up_s=$(cut -d. -f1 /host/uptime)
  host_uptime="${up_s}s"
  if [ "$up_s" -lt 600 ]; then
    ip_note="${ip_note}; Pi uptime ${up_s}s (recent reboot)"
  fi
fi

result=OK
reason_block="  (none)"
if [ "$ok" -ne 1 ]; then
  result=FAIL
  reason_block=$(printf '%b' "$reasons" | sed '/^$/d')
fi

recent_logs=""
if [ "$result" = FAIL ] && docker inspect "$WG_CONTAINER" >/dev/null 2>&1; then
  recent_logs=$(docker logs --tail 40 "$WG_CONTAINER" 2>&1 || true)
fi

report=$(printf '%s\n' \
  "time: $STAMP" \
  "result: $result" \
  "public_ip: $pubip" \
  "ip_note: $ip_note" \
  "host_uptime: $host_uptime" \
  "container: $container_state" \
  "reasons:" \
  "$reason_block" \
  "" \
  "wg show:" \
  "$wg_out")

if [ -n "$recent_logs" ]; then
  report=$(printf '%s\n\n%s\n%s\n' "$report" "wg-easy logs (last 40):" "$recent_logs")
fi

printf '%s\n---\n' "$report" >> "$LOGDIR/status.log"
if [ "$(wc -l < "$LOGDIR/status.log")" -gt 4000 ]; then
  tail -n 2000 "$LOGDIR/status.log" > "$LOGDIR/status.log.tmp"
  mv "$LOGDIR/status.log.tmp" "$LOGDIR/status.log"
fi
touch "$LOGDIR/heartbeat"

# Healthchecks.io (or any compatible ping URL). Body is the snapshot.
if [ -n "${HEALTHCHECKS_URL:-}" ]; then
  ping_url="$HEALTHCHECKS_URL"
  if [ "$result" = FAIL ]; then
    ping_url="${HEALTHCHECKS_URL%/}/fail"
  fi
  printf '%s\n' "$report" | curl -fsS -m 15 --retry 2 -X POST --data-binary @- "$ping_url" >/dev/null \
    || printf '%s healthchecks ping failed\n' "$STAMP" >> "$LOGDIR/notify.log"
fi

state_file="$LOGDIR/last-result"
prev=""
if [ -f "$state_file" ]; then
  prev=$(cat "$state_file")
fi
printf '%s\n' "$result" > "$state_file"

# Push only on transition so a down container does not spam every loop.
if [ "$result" != "$prev" ] && [ -n "$prev" ]; then
  title="Pi WireGuard $result"
  if [ -n "${NTFY_TOPIC:-}" ]; then
    printf '%s\n' "$report" | curl -fsS -m 15 --retry 2 \
      -H "Title: $title" \
      -H "Priority: $([ "$result" = FAIL ] && echo urgent || echo default)" \
      -d @- "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null \
      || printf '%s ntfy failed\n' "$STAMP" >> "$LOGDIR/notify.log"
  fi
  if [ -n "${SIGNAL_ACCOUNT:-}" ] && [ -n "${SIGNAL_RECIPIENT:-}" ] && command -v jq >/dev/null 2>&1; then
    # Keep the Signal body short; full snapshot is in the local log / Healthchecks.
    msg=$(printf '%s\n%s\n%s\n' "$title" "$STAMP" "$reason_block")
    payload=$(jq -n --arg message "$msg" --arg number "$SIGNAL_ACCOUNT" --arg recipient "$SIGNAL_RECIPIENT" \
      '{message: $message, number: $number, recipients: [$recipient]}')
    printf '%s\n' "$payload" | curl -fsS -m 20 --retry 2 -X POST \
      -H "Content-Type: application/json" \
      -d @- "${SIGNAL_API_URL}/v2/send" >/dev/null \
      || printf '%s signal failed\n' "$STAMP" >> "$LOGDIR/notify.log"
  fi
fi

if [ "$result" = FAIL ]; then
  exit 1
fi
