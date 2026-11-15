#!/usr/bin/env bash
#
# DOCKER_STARTUP — one command to set up your local dev services.
#
#   ./setup.sh                        interactive: pick services -> configure -> start -> show connection info
#   ./setup.sh postgres redis otel    start exactly these (no questions asked)
#   ./setup.sh --all                  start everything
#   ./setup.sh --yes                  use your last selection (or the defaults) without prompts
#   ./setup.sh up|down|restart|status|logs [service]|info|clean|help
#
# Works with the bash that ships with macOS (3.2), Linux and WSL.
set -euo pipefail
set -f # no filename globbing: we never need it, and it keeps typed input safe

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"

ALL_ITEMS="postgres mysql mongo redis neo4j adminer mailpit rabbitmq livekit otel elk"
DEFAULT_ITEMS="postgres redis adminer mailpit"

# ----------------------------------------------------------------------------
# Configuration variables: NAME=default  (also used to generate .env.example)
# ----------------------------------------------------------------------------
CONFIG_SPEC='
# Network: 127.0.0.1 = only this machine can connect. 0.0.0.0 = anyone on your network.
BIND_IP=127.0.0.1

# PostgreSQL (+ pgvector)
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres

# MySQL
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD=mysql
MYSQL_DATABASE=app

# MongoDB (no auth)
MONGO_PORT=27017

# Redis
REDIS_PORT=6379

# Neo4j (password must be 8+ characters)
NEO4J_HTTP_PORT=7474
NEO4J_BOLT_PORT=7687
NEO4J_PASSWORD=password123

# Adminer (database web UI)
ADMINER_PORT=4000
ADMINER_DESIGN=flat
ADMINER_DEFAULT_SERVER=postgres

# Mailpit (catches all outgoing email)
MAILPIT_SMTP_PORT=1025
MAILPIT_UI_PORT=8025

# RabbitMQ
RABBITMQ_PORT=5672
RABBITMQ_UI_PORT=15672
RABBITMQ_USER=admin
RABBITMQ_PASSWORD=admin

# LiveKit (dev mode: key devkey / secret secret)
LIVEKIT_PORT=7880
LIVEKIT_RTC_TCP_PORT=7881
LIVEKIT_RTC_UDP_PORT=7882

# Observability (OpenTelemetry Collector, Prometheus, Grafana, Jaeger)
OTEL_GRPC_PORT=4317
OTEL_HTTP_PORT=4318
PROMETHEUS_PORT=9090
JAEGER_UI_PORT=16686
GRAFANA_PORT=4444
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin

# Elasticsearch + Kibana
ELK_VERSION=9.5.5
ES_PORT=9200
ES_HEAP=512m
KIBANA_PORT=5601
'

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m' D=$'\033[2m' R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' C=$'\033[36m' N=$'\033[0m'
else
  B='' D='' R='' G='' Y='' C='' N=''
fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$C" "$N" "$*"; }
ok()   { printf '%s ✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s !%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s ✖ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

ASSUME_YES=0

# ask VAR "Question" "default" — Enter keeps the default. Reads stdin, so answers can be piped in.
ask() {
  local _answer=""
  if [ "$ASSUME_YES" = 1 ]; then printf -v "$1" '%s' "$3"; return 0; fi
  printf '%s %s[%s]%s: ' "$2" "$D" "$3" "$N" >&2
  IFS= read -r _answer || _answer=""
  [ -z "$_answer" ] && _answer=$3
  printf -v "$1" '%s' "$_answer"
}

# confirm "Question" y|n  — returns 0 for yes
confirm() {
  local _answer="" _hint="[y/N]"
  [ "$2" = y ] && _hint="[Y/n]"
  if [ "$ASSUME_YES" = 1 ]; then [ "$2" = y ]; return; fi
  printf '%s %s: ' "$1" "$_hint" >&2
  IFS= read -r _answer || _answer=""
  [ -z "$_answer" ] && _answer=$2
  case "$_answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ----------------------------------------------------------------------------
# Service catalogue
# ----------------------------------------------------------------------------
item_desc() {
  case "$1" in
    postgres) echo "PostgreSQL 17 + pgvector" ;;
    mysql)    echo "MySQL 8.4" ;;
    mongo)    echo "MongoDB 8.0" ;;
    redis)    echo "Redis 7.4" ;;
    neo4j)    echo "Neo4j 5 graph database + APOC" ;;
    adminer)  echo "Adminer - web UI for Postgres / MySQL" ;;
    mailpit)  echo "Mailpit - fake SMTP server + web inbox" ;;
    rabbitmq) echo "RabbitMQ 4 + management UI" ;;
    livekit)  echo "LiveKit - WebRTC / video server (dev mode)" ;;
    otel)     echo "OpenTelemetry Collector + Prometheus + Grafana + Jaeger" ;;
    elk)      echo "Elasticsearch + Kibana (needs ~2 GB RAM)" ;;
  esac
}

item_group() {
  case "$1" in
    postgres|mysql|mongo|redis|neo4j) echo "Databases" ;;
    otel|elk) echo "Monitoring" ;;
    *) echo "Tools" ;;
  esac
}

# Which compose stack an item lives in
item_stack() {
  case "$1" in otel) echo otel ;; elk) echo elk ;; *) echo common ;; esac
}

stack_file() {
  case "$1" in
    common) echo "$ROOT/common-docker-services/docker-compose.yml" ;;
    otel)   echo "$ROOT/app-monitoring/otel/docker-compose.yml" ;;
    elk)    echo "$ROOT/app-monitoring/elk/docker-compose.yml" ;;
  esac
}

# Container names (fixed via container_name in the compose files)
item_containers() {
  case "$1" in
    otel) echo "otel-collector jaeger prometheus grafana" ;;
    elk)  echo "elasticsearch kibana" ;;
    *)    echo "$1" ;;
  esac
}

# Host TCP ports an item publishes (config variable names)
item_ports() {
  case "$1" in
    postgres) echo "POSTGRES_PORT" ;;
    mysql)    echo "MYSQL_PORT" ;;
    mongo)    echo "MONGO_PORT" ;;
    redis)    echo "REDIS_PORT" ;;
    neo4j)    echo "NEO4J_HTTP_PORT NEO4J_BOLT_PORT" ;;
    adminer)  echo "ADMINER_PORT" ;;
    mailpit)  echo "MAILPIT_SMTP_PORT MAILPIT_UI_PORT" ;;
    rabbitmq) echo "RABBITMQ_PORT RABBITMQ_UI_PORT" ;;
    livekit)  echo "LIVEKIT_PORT LIVEKIT_RTC_TCP_PORT" ;;
    otel)     echo "OTEL_GRPC_PORT OTEL_HTTP_PORT PROMETHEUS_PORT JAEGER_UI_PORT GRAFANA_PORT" ;;
    elk)      echo "ES_PORT KIBANA_PORT" ;;
  esac
}

# Settings offered in the "customize" step
item_settings() {
  case "$1" in
    postgres) echo "POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB" ;;
    mysql)    echo "MYSQL_PORT MYSQL_ROOT_PASSWORD MYSQL_DATABASE" ;;
    mongo)    echo "MONGO_PORT" ;;
    redis)    echo "REDIS_PORT" ;;
    neo4j)    echo "NEO4J_HTTP_PORT NEO4J_BOLT_PORT NEO4J_PASSWORD" ;;
    adminer)  echo "ADMINER_PORT ADMINER_DESIGN ADMINER_DEFAULT_SERVER" ;;
    mailpit)  echo "MAILPIT_SMTP_PORT MAILPIT_UI_PORT" ;;
    rabbitmq) echo "RABBITMQ_PORT RABBITMQ_UI_PORT RABBITMQ_USER RABBITMQ_PASSWORD" ;;
    livekit)  echo "LIVEKIT_PORT LIVEKIT_RTC_TCP_PORT LIVEKIT_RTC_UDP_PORT" ;;
    otel)     echo "OTEL_GRPC_PORT OTEL_HTTP_PORT PROMETHEUS_PORT JAEGER_UI_PORT GRAFANA_PORT GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD" ;;
    elk)      echo "ES_PORT KIBANA_PORT ES_HEAP" ;;
  esac
}

is_item() { case " $ALL_ITEMS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
has()     { case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }

# Normalise a list: expand aliases, drop duplicates, keep catalogue order
normalize_items() {
  local wanted="" word out=""
  for word in "$@"; do
    case "$word" in
      all)                wanted="$wanted $ALL_ITEMS" ;;
      db|dbs|databases)   wanted="$wanted postgres mysql mongo redis neo4j" ;;
      monitoring)         wanted="$wanted otel elk" ;;
      mailhog)            wanted="$wanted mailpit" ;;
      *)
        is_item "$word" || die "Unknown service '$word'. Choose from: $ALL_ITEMS (or: all, db, monitoring)"
        wanted="$wanted $word" ;;
    esac
  done
  for word in $ALL_ITEMS; do has "$wanted" "$word" && out="$out $word"; done
  echo "${out# }"
}

# ----------------------------------------------------------------------------
# .env handling (one file for every stack)
# ----------------------------------------------------------------------------
CONFIG_VARS=" $(printf '%s\n' "$CONFIG_SPEC" | sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' | xargs) "
is_config_var() { has "$CONFIG_VARS" "$1"; }

load_defaults() {
  local line
  while IFS= read -r line; do
    case "$line" in [A-Z]*=*) printf -v "${line%%=*}" '%s' "${line#*=}" ;; esac
  done <<EOF
$CONFIG_SPEC
EOF
  SERVICES=""
}

# Parse .env without executing it. Accepts KEY=value, KEY='value', KEY="value".
load_env() {
  local line key val
  [ -f "$ENV_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in ''|'#'*) continue ;; esac
    key=${line%%=*}
    val=${line#*=}
    case "$key" in *[!A-Za-z0-9_]*|'') continue ;; esac
    case "$val" in
      \'*\') val=${val#\'}; val=${val%\'} ;;
      \"*\") val=${val#\"}; val=${val%\"} ;;
    esac
    if [ "$key" = SERVICES ] || is_config_var "$key"; then printf -v "$key" '%s' "$val"; fi
  done < "$ENV_FILE"
}

# Print the env file (current values). With "example", print defaults + header for .env.example.
render_env() {
  local line key
  if [ "${1:-}" = example ]; then
    say "# Copy to .env (or just run ./setup.sh, which writes .env for you)."
    say "# Every variable is optional: the compose files fall back to these same defaults."
    say ""
    say "# Services ./setup.sh up starts (space separated): $ALL_ITEMS"
    say "SERVICES='$DEFAULT_ITEMS'"
  else
    say "# Written by ./setup.sh — edit freely, then run ./setup.sh up (or re-run ./setup.sh)."
    say "# Values are single-quoted so Docker Compose takes them literally."
    say ""
    say "# Services ./setup.sh up starts (space separated): $ALL_ITEMS"
    say "SERVICES='$SERVICES'"
  fi
  while IFS= read -r line; do
    case "$line" in
      [A-Z]*=*)
        key=${line%%=*}
        if [ "${1:-}" = example ]; then say "$key='${line#*=}'"; else say "$key='${!key}'"; fi ;;
      *) say "$line" ;;
    esac
  done <<EOF
$CONFIG_SPEC
EOF
}

save_env() {
  render_env > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  ok "Saved settings to .env"
}

compose() { # compose <stack> <args...>
  local stack=$1; shift
  if [ -f "$ENV_FILE" ]; then
    dk compose --env-file "$ENV_FILE" -f "$(stack_file "$stack")" "$@"
  else
    dk compose -f "$(stack_file "$stack")" "$@"
  fi
}

# ----------------------------------------------------------------------------
# Docker preflight
# ----------------------------------------------------------------------------
USE_SUDO=0
dk() { if [ "$USE_SUDO" = 1 ]; then sudo docker "$@"; else docker "$@"; fi; }

detect_os() {
  case "$(uname -s)" in
    Darwin) OS=mac ;;
    Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then OS=wsl; else OS=linux; fi ;;
    *)      OS=other ;;
  esac
}

install_docker_linux() {
  local script
  command -v curl >/dev/null 2>&1 || die "curl is required to install Docker. Install curl and re-run."
  script="$(mktemp)"
  info "Downloading Docker's official install script (https://get.docker.com)"
  curl -fsSL https://get.docker.com -o "$script"
  info "Installing Docker Engine + Compose plugin (you may be asked for your sudo password)"
  sudo sh "$script"
  rm -f "$script"
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl enable --now docker
  else
    sudo service docker start || true
  fi
  if ! has "$(id -nG)" docker; then
    sudo usermod -aG docker "$(id -un)"
    warn "Added $(id -un) to the 'docker' group. Log out and back in (or run: newgrp docker) to use docker without sudo."
  fi
  ok "Docker installed"
}

ensure_docker() {
  local saved_yes=$ASSUME_YES
  detect_os
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker is not installed."
    [ -t 0 ] && ASSUME_YES=0 # installing software always asks when someone is at the terminal
    case "$OS" in
      mac)
        if command -v brew >/dev/null 2>&1 && confirm "Install Docker Desktop with Homebrew (brew install --cask docker)?" y; then
          brew install --cask docker
        else
          die "Install Docker Desktop from https://docs.docker.com/desktop/setup/install/mac-install/ and re-run ./setup.sh"
        fi ;;
      linux|wsl)
        if [ "$OS" = wsl ]; then
          say "   Tip: on WSL the smoothest option is Docker Desktop for Windows with WSL integration:"
          say "   https://docs.docker.com/desktop/features/wsl/  (you can also install Docker Engine inside WSL)."
        fi
        if confirm "Install Docker Engine + Compose now with Docker's official script (needs sudo)?" y; then
          install_docker_linux
        else
          die "Install Docker from https://docs.docker.com/engine/install/ and re-run ./setup.sh"
        fi ;;
      *) die "Unsupported OS. Install Docker from https://docs.docker.com/get-docker/" ;;
    esac
    ASSUME_YES=$saved_yes
  fi

  if ! docker info >/dev/null 2>&1; then
    if [ "$OS" != mac ] && sudo -n true 2>/dev/null && sudo docker info >/dev/null 2>&1; then
      USE_SUDO=1
      warn "Your user can't talk to Docker yet, so this run uses sudo. Log out/in (or 'newgrp docker') to fix that."
    else
      start_docker_daemon
    fi
  fi

  dk compose version >/dev/null 2>&1 || die "Docker Compose v2 is missing. See https://docs.docker.com/compose/install/"
}

start_docker_daemon() {
  local waited=0
  case "$OS" in
    mac)
      info "Docker isn't running — starting Docker Desktop"
      open -a Docker 2>/dev/null || die "Couldn't start Docker Desktop. Start your Docker app (Docker Desktop / OrbStack / Colima) and re-run."
      ;;
    linux|wsl)
      info "Docker isn't running — starting the Docker service (sudo)"
      if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        sudo systemctl start docker || true
      else
        sudo service docker start || true
      fi
      if ! docker info >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
        USE_SUDO=1
        warn "Using sudo for docker in this run. Log out/in (or 'newgrp docker') to use docker without sudo."
        return 0
      fi
      [ "$OS" = wsl ] && ! docker info >/dev/null 2>&1 && \
        warn "On WSL with Docker Desktop: start Docker Desktop on Windows and enable WSL integration for this distro."
      ;;
  esac
  printf '   waiting for Docker'
  while ! dk info >/dev/null 2>&1; do
    if [ "$waited" -ge 90 ]; then printf '\n'; die "Docker didn't start within 90s. Start it manually and re-run ./setup.sh"; fi
    printf '.'; sleep 3; waited=$((waited + 3))
  done
  printf '\n'; ok "Docker is running"
}

# ----------------------------------------------------------------------------
# Interactive service picker
# ----------------------------------------------------------------------------
pick_services() {
  local selected="$1" i item group last_group mark answer word n
  while :; do
    say ""
    say "${B}Pick the services you want${N}  ${D}(numbers toggle, e.g. \"1 3 10\" · a = all · n = none · Enter = done)${N}"
    i=0; last_group=""
    for item in $ALL_ITEMS; do
      i=$((i + 1))
      group=$(item_group "$item")
      if [ "$group" != "$last_group" ]; then say ""; say "  ${B}$group${N}"; last_group=$group; fi
      if has "$selected" "$item"; then mark="${G}[x]${N}"; else mark="[ ]"; fi
      printf '   %s %2d) %-9s %s%s%s\n' "$mark" "$i" "$item" "$D" "$(item_desc "$item")" "$N"
    done
    say ""
    printf '> ' >&2
    if ! IFS= read -r answer && [ -z "$answer" ]; then
      [ -n "$selected" ] || die "No input — nothing selected."
      answer=""
    fi
    case "$answer" in
      '')
        if [ -z "$selected" ]; then warn "Nothing selected — pick at least one service."; continue; fi
        # shellcheck disable=SC2086
        PICKED=$(normalize_items $selected); return 0 ;;
      a|A|all) selected=$ALL_ITEMS; continue ;;
      n|N|none) selected=""; continue ;;
    esac
    for word in $answer; do
      word=${word%,}
      case "$word" in *[!0-9]*|'') warn "Ignoring '$word' (type numbers)"; continue ;; esac
      n=0; item=""
      for item in $ALL_ITEMS; do n=$((n + 1)); [ "$n" -eq "$word" ] && break; done
      if [ "$word" -lt 1 ] || [ "$word" -gt "$n" ]; then warn "No service number $word"; continue; fi
      if has "$selected" "$item"; then
        selected=$(echo " $selected " | sed "s/ $item / /" | xargs)
      else
        selected="$selected $item"
      fi
    done
  done
}

customize() {
  local item var val label
  for item in $SERVICES; do
    say ""; say "  ${B}$item${N}"
    for var in $(item_settings "$item"); do
      label=$(echo "$var" | tr '_' ' ' | tr '[:upper:]' '[:lower:]')
      while :; do
        ask val "    $label" "${!var}"
        case "$val" in
          *"'"*|*' '*) warn "Spaces and single quotes aren't allowed here." ; continue ;;
        esac
        case "$var" in
          *_PORT) case "$val" in ''|*[!0-9]*) warn "Port must be a number."; continue ;; esac ;;
          NEO4J_PASSWORD) [ "${#val}" -ge 8 ] || { warn "Neo4j needs at least 8 characters."; continue; } ;;
        esac
        break
      done
      printf -v "$var" '%s' "$val"
    done
  done
}

# ----------------------------------------------------------------------------
# Port checks
# ----------------------------------------------------------------------------
port_listening() {
  if command -v lsof >/dev/null 2>&1 && [ "$OS" = mac ]; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v ss >/dev/null 2>&1; then
    [ -n "$(ss -Hltn "sport = :$1" 2>/dev/null)" ]
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}

# Who is using a port? Prints a container name, or nothing.
port_container() { local out; out=$(dk ps --filter "publish=$1" --format '{{.Names}}' 2>/dev/null || true); echo "${out%%$'\n'*}"; }

free_port_after() {
  local p=$(( $1 + 1 ))
  while port_listening "$p" || has "$RESERVED_PORTS" "$p"; do p=$((p + 1)); done
  echo "$p"
}

check_ports() {
  local item var port owner newp
  RESERVED_PORTS=""
  for item in $SERVICES; do
    for var in $(item_ports "$item"); do
      port=${!var}
      if has "$RESERVED_PORTS" "$port"; then
        newp=$(free_port_after "$port")
        warn "$var=$port is used twice in your settings — using $newp instead."
        printf -v "$var" '%s' "$newp"; port=$newp
      elif port_listening "$port"; then
        owner=$(port_container "$port")
        if [ -n "$owner" ] && has "$(item_containers "$item")" "$owner"; then
          :  # it's our own container — fine
        else
          newp=$(free_port_after "$port")
          if [ -n "$owner" ]; then owner=" by container \"$owner\""; fi
          warn "Port $port ($var) is already in use$owner."
          ask newp "    Use another port for $var" "$newp"
          printf -v "$var" '%s' "$newp"; port=$newp
        fi
      fi
      RESERVED_PORTS="$RESERVED_PORTS $port"
    done
  done
}

check_memory() {
  local mem
  has "$SERVICES" elk || return 0
  mem=$(dk info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  if [ "${mem:-0}" -gt 0 ] && [ "$mem" -lt 3500000000 ]; then
    warn "Docker has only $((mem / 1024 / 1024)) MB of memory. Elasticsearch + Kibana need ~2 GB free; give Docker 4 GB+ if they crash."
  fi
}

# ----------------------------------------------------------------------------
# Start / stop / wait
# ----------------------------------------------------------------------------
common_services_in() { local out="" i; for i in $1; do [ "$(item_stack "$i")" = common ] && out="$out $i"; done; echo "${out# }"; }

start_services() {
  local common running to_remove="" item
  common=$(common_services_in "$SERVICES")

  # Remove services you de-selected so what's running matches your choice (data volumes are kept).
  running=$(compose common ps --services 2>/dev/null || true)
  for item in $running; do has "$common" "$item" || to_remove="$to_remove $item"; done
  for item in otel elk; do
    if ! has "$SERVICES" "$item" && [ -n "$(compose "$item" ps -q 2>/dev/null)" ]; then to_remove="$to_remove $item"; fi
  done
  to_remove=${to_remove# }
  if [ -n "$to_remove" ]; then
    if confirm "Running but not picked: $to_remove. Stop them? (their data is kept)" y; then
      for item in $to_remove; do
        case "$item" in
          otel|elk) compose "$item" down >/dev/null 2>&1 || true ;;
          *) compose common rm -sf "$item" >/dev/null 2>&1 || true ;;
        esac
        ok "Stopped $item"
      done
    fi
  fi

  if [ -n "$common" ]; then
    info "Starting: $common"
    # shellcheck disable=SC2086
    compose common up -d $common
  fi
  for item in otel elk; do
    if has "$SERVICES" "$item"; then
      info "Starting: $item ($(item_containers "$item"))"
      compose "$item" up -d
    fi
  done
}

wait_healthy() {
  local item c status start timeout failed=0
  say ""
  info "Waiting for services to be ready"
  for item in $SERVICES; do
    timeout=120; [ "$item" = elk ] && timeout=300
    for c in $(item_containers "$item"); do
      start=$SECONDS
      while :; do
        status=$(dk inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null || echo missing)
        case "$status" in
          healthy|running) ok "$c ${D}($((SECONDS - start))s)${N}"; break ;;
          unhealthy|exited|dead|missing)
            warn "$c is $status — last log lines:"; dk logs --tail 25 "$c" 2>&1 | sed 's/^/      /' >&2 || true
            failed=1; break ;;
        esac
        if [ $((SECONDS - start)) -ge "$timeout" ]; then
          warn "$c still '$status' after ${timeout}s — check: ./setup.sh logs $c"; failed=1; break
        fi
        sleep 2
      done
    done
  done
  return "$failed"
}

stop_all() {
  local stack
  for stack in elk otel common; do
    if [ -n "$(compose "$stack" ps -aq 2>/dev/null)" ]; then
      info "Stopping $stack"
      compose "$stack" down
    fi
  done
  ok "Everything is stopped. Your data is kept (./setup.sh up to start again)."
}

# ----------------------------------------------------------------------------
# Connection info
# ----------------------------------------------------------------------------
print_info() {
  local h=localhost item
  [ "$BIND_IP" != 0.0.0.0 ] && [ "$BIND_IP" != 127.0.0.1 ] && h=$BIND_IP
  say ""
  say "${B}Your services${N}"
  say ""
  for item in $SERVICES; do
    case "$item" in
      postgres) printf '  %-10s %s\n' postgres "postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$h:$POSTGRES_PORT/$POSTGRES_DB" ;;
      mysql)    printf '  %-10s %s\n' mysql "mysql://root:$MYSQL_ROOT_PASSWORD@$h:$MYSQL_PORT/$MYSQL_DATABASE" ;;
      mongo)    printf '  %-10s %s\n' mongo "mongodb://$h:$MONGO_PORT" ;;
      redis)    printf '  %-10s %s\n' redis "redis://$h:$REDIS_PORT" ;;
      neo4j)    printf '  %-10s %s\n' neo4j "http://$h:$NEO4J_HTTP_PORT  ·  bolt://$h:$NEO4J_BOLT_PORT  ·  neo4j / $NEO4J_PASSWORD" ;;
      adminer)  printf '  %-10s %s\n' adminer "http://$h:$ADMINER_PORT  (server: postgres or mysql)" ;;
      mailpit)  printf '  %-10s %s\n' mailpit "inbox http://$h:$MAILPIT_UI_PORT  ·  SMTP $h:$MAILPIT_SMTP_PORT (any user/pass)" ;;
      rabbitmq) printf '  %-10s %s\n' rabbitmq "amqp://$RABBITMQ_USER:$RABBITMQ_PASSWORD@$h:$RABBITMQ_PORT  ·  UI http://$h:$RABBITMQ_UI_PORT" ;;
      livekit)  printf '  %-10s %s\n' livekit "ws://$h:$LIVEKIT_PORT  ·  API key devkey / secret secret" ;;
      otel)
        printf '  %-10s %s\n' otel "send OTLP to http://$h:$OTEL_HTTP_PORT (HTTP) or $h:$OTEL_GRPC_PORT (gRPC)"
        printf '  %-10s %s\n' "" "Grafana http://$h:$GRAFANA_PORT ($GRAFANA_ADMIN_USER / $GRAFANA_ADMIN_PASSWORD)"
        printf '  %-10s %s\n' "" "Jaeger http://$h:$JAEGER_UI_PORT  ·  Prometheus http://$h:$PROMETHEUS_PORT" ;;
      elk)      printf '  %-10s %s\n' elk "Elasticsearch http://$h:$ES_PORT  ·  Kibana http://$h:$KIBANA_PORT" ;;
    esac
  done
  say ""
  if [ -n "$(common_services_in "$SERVICES")" ]; then
    say "  ${D}From another container on the 'app' network, use the service name as host (e.g. postgres:5432).${N}"
  fi
  say "  ${D}Manage: ./setup.sh status | logs <service> | down | up    ·    Settings: .env${N}"
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------
usage() {
  cat <<EOF
${B}DOCKER_STARTUP setup${N} — local dev services in one command

Usage:
  ./setup.sh                       Interactive: pick services, configure, start
  ./setup.sh <service>...          Start exactly these services (no questions)
  ./setup.sh --all                 Start everything
  ./setup.sh --yes                 Re-use your last selection (or defaults) without prompts

  ./setup.sh up                    Start the services saved in .env
  ./setup.sh down                  Stop everything (data is kept)
  ./setup.sh restart               Restart the services saved in .env
  ./setup.sh status                Show what's running
  ./setup.sh logs [service]        Follow logs (e.g. ./setup.sh logs postgres)
  ./setup.sh info                  Show URLs, connection strings and credentials
  ./setup.sh clean                 Stop everything and DELETE all data volumes
  ./setup.sh help                  This help

Services: $ALL_ITEMS
Aliases:  all, db (all databases), monitoring (otel + elk)
EOF
}

cmd_setup() { # cmd_setup <interactive 0|1> [items...]
  local interactive=$1; shift
  ensure_docker
  load_defaults
  load_env

  if [ "$#" -gt 0 ]; then
    SERVICES=$(normalize_items "$@")
  elif [ "$interactive" = 1 ]; then
    say ""
    say "${B}DOCKER_STARTUP${N} — local dev services in one command"
    pick_services "${SERVICES:-$DEFAULT_ITEMS}"
    SERVICES=$PICKED
    say ""
    ok "Selected: $SERVICES"
    if confirm "Customize ports / passwords? (Enter = keep defaults)" n; then customize; fi
  else
    # shellcheck disable=SC2086
    SERVICES=$(normalize_items ${SERVICES:-$DEFAULT_ITEMS})
  fi
  [ -n "$SERVICES" ] || die "No services selected."

  check_ports
  check_memory
  save_env
  start_services
  if wait_healthy; then
    print_info
    say ""; ok "${B}All set!${N}"
  else
    print_info
    say ""; die "Some services didn't become ready (see above). Try: ./setup.sh logs <service>"
  fi
}

cmd_status() {
  local stack any=0
  ensure_docker
  for stack in common otel elk; do
    if [ -n "$(compose "$stack" ps -aq 2>/dev/null)" ]; then
      any=1
      say ""; say "${B}$stack${N}"
      compose "$stack" ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
    fi
  done
  [ "$any" = 1 ] || say "Nothing is running. Start with ./setup.sh"
}

cmd_logs() {
  local svc=${1:-} stack
  ensure_docker
  if [ -z "$svc" ]; then compose common logs -f --tail 100; return; fi
  for stack in common otel elk; do
    if has "$(compose "$stack" config --services 2>/dev/null | xargs)" "$svc"; then
      compose "$stack" logs -f --tail 200 "$svc"; return
    fi
  done
  die "Unknown service '$svc'. Try one of: $(for s in common otel elk; do compose "$s" config --services 2>/dev/null; done | xargs)"
}

cmd_restart() {
  local common item
  ensure_docker; load_defaults; load_env
  [ -n "$SERVICES" ] || die "Nothing configured yet. Run ./setup.sh first."
  common=$(common_services_in "$SERVICES")
  # shellcheck disable=SC2086
  [ -n "$common" ] && compose common restart $common
  for item in otel elk; do has "$SERVICES" "$item" && compose "$item" restart; done
  wait_healthy || true
  print_info
}

cmd_clean() {
  local answer=""
  ensure_docker
  warn "This stops every service AND permanently deletes their data volumes (databases, queues, dashboards...)."
  printf 'Type "delete" to confirm: ' >&2
  IFS= read -r answer || answer=""
  [ "$answer" = delete ] || die "Cancelled — nothing was deleted."
  local stack
  for stack in elk otel common; do compose "$stack" down -v --remove-orphans; done
  ok "All containers and data volumes removed."
}

main() {
  local cmd=${1:-} items=""
  case "$cmd" in
    up)        shift; ASSUME_YES=1; cmd_setup 0 ;;
    down|stop) ensure_docker; stop_all ;;
    restart)   cmd_restart ;;
    status|ps) cmd_status ;;
    logs)      shift; cmd_logs "${1:-}" ;;
    info)      load_defaults; load_env; [ -n "$SERVICES" ] || die "Nothing configured yet. Run ./setup.sh first."; print_info ;;
    clean)     cmd_clean ;;
    help|-h|--help) usage ;;
    _env-example) load_defaults; render_env example ;;
    *)
      while [ "$#" -gt 0 ]; do
        case "$1" in
          setup) ;;
          -y|--yes) ASSUME_YES=1 ;;
          -a|--all) ASSUME_YES=1; items="$items all" ;;
          -*) die "Unknown option '$1'. See ./setup.sh help" ;;
          *) ASSUME_YES=1; items="$items $1" ;;
        esac
        shift
      done
      if [ "$ASSUME_YES" = 1 ]; then
        # shellcheck disable=SC2086
        cmd_setup 0 $items
      else
        cmd_setup 1
      fi ;;
  esac
}

main "$@"
