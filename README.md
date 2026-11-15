# DOCKER_STARTUP

[![CI](https://github.com/farzanhossan/DOCKER_STARTUP/actions/workflows/ci.yml/badge.svg)](https://github.com/farzanhossan/DOCKER_STARTUP/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Pick the local dev services you need — databases, queues, mail catcher, monitoring — and get them running with one command.**

No copy-pasting compose files between projects, no remembering ports and passwords. Run `./setup.sh`, tick what you want, and it prints the connection strings when everything is healthy.

```text
$ ./setup.sh

Pick the services you want  (numbers toggle, e.g. "1 3 10" · a = all · n = none · Enter = done)

  Databases
   [x]  1) postgres  PostgreSQL 17 + pgvector
   [ ]  2) mysql     MySQL 8.4
   [ ]  3) mongo     MongoDB 8.0
   [x]  4) redis     Redis 7.4
   [ ]  5) neo4j     Neo4j 5 graph database + APOC

  Tools
   [x]  6) adminer   Adminer - web UI for Postgres / MySQL
   [x]  7) mailpit   Mailpit - fake SMTP server + web inbox
   [ ]  8) rabbitmq  RabbitMQ 4 + management UI
   [ ]  9) livekit   LiveKit - WebRTC / video server (dev mode)

  Monitoring
   [ ] 10) otel      OpenTelemetry Collector + Prometheus + Grafana + Jaeger
   [ ] 11) elk       Elasticsearch + Kibana (needs ~2 GB RAM)
>
```

---

## Quick start

**One line** (macOS, Linux, WSL):

```bash
curl -fsSL https://raw.githubusercontent.com/farzanhossan/DOCKER_STARTUP/main/install.sh | bash
```

This downloads the repo to `~/docker-startup` and runs the setup. Prefer to look first? [`install.sh`](install.sh) only clones this repo and runs `setup.sh`.

**Or clone it yourself:**

```bash
git clone https://github.com/farzanhossan/DOCKER_STARTUP.git
cd DOCKER_STARTUP
./setup.sh
```

`setup.sh` will:

1. **Check Docker** — installs it if missing (Linux/WSL via Docker's official script, macOS via Homebrew — always asks first) and starts it if it isn't running.
2. **Let you pick services** from the menu above (your last choice is remembered).
3. **Optionally customize** ports and passwords — just press Enter to keep the defaults.
4. **Check for port conflicts** and offer a free port if something else is already using one.
5. **Start** only what you picked, **wait until each service is healthy**, and **print connection info**.

---

## What's included

| Service | What it is | Port(s) on localhost | Open / connect | Default login |
|---|---|---|---|---|
| `postgres` | PostgreSQL 17 + [pgvector](https://github.com/pgvector/pgvector) | 5432 | `postgres://postgres:postgres@localhost:5432/postgres` | `postgres` / `postgres` |
| `mysql` | MySQL 8.4 LTS | 3306 | `mysql://root:mysql@localhost:3306/app` | `root` / `mysql` |
| `mongo` | MongoDB 8.0 | 27017 | `mongodb://localhost:27017` | no auth |
| `redis` | Redis 7.4 | 6379 | `redis://localhost:6379` | no auth |
| `neo4j` | Neo4j 5 + APOC | 7474, 7687 | http://localhost:7474 · `bolt://localhost:7687` | `neo4j` / `password123` |
| `adminer` | DB web UI (Postgres, MySQL, …) | 4000 | http://localhost:4000 | use the DB's login |
| `mailpit` | Catches every email your app sends | 1025 (SMTP), 8025 (UI) | http://localhost:8025 | any SMTP user/pass |
| `rabbitmq` | RabbitMQ 4 + management UI | 5672, 15672 | http://localhost:15672 · `amqp://admin:admin@localhost:5672` | `admin` / `admin` |
| `livekit` | LiveKit WebRTC server (dev mode) | 7880, 7881, 7882/udp | `ws://localhost:7880` | key `devkey` / secret `secret` |
| `otel` | OTel Collector + Prometheus + Grafana + Jaeger | 4317, 4318, 9090, 4444, 16686 | Grafana http://localhost:4444 · Jaeger http://localhost:16686 · Prometheus http://localhost:9090 | Grafana `admin` / `admin` |
| `elk` | Elasticsearch 9 + Kibana | 9200, 5601 | http://localhost:9200 · Kibana http://localhost:5601 | no auth |

All versions are pinned, so nothing changes under you when an image publishes a new major version. Everything runs on Apple Silicon and x86.

---

## The setup command

```bash
./setup.sh                          # interactive menu
./setup.sh postgres redis           # start exactly these, no questions
./setup.sh db                       # all databases   (aliases: all, db, monitoring)
./setup.sh --all                    # everything
./setup.sh --yes                    # your last selection (or the defaults), no questions
```

When you pass service names, that list becomes your selection: services you didn't list are stopped (their data is kept). In the interactive menu you're asked before anything is stopped.

### Everyday commands

| `./setup.sh …` | `make …` | What it does |
|---|---|---|
| *(no args)* | `make setup` | Interactive setup |
| `up` | `make up` | Start the services you picked last time |
| `postgres redis` | `make up s="postgres redis"` | Start exactly these |
| `down` | `make down` | Stop everything — **data is kept** |
| `restart` | `make restart` | Restart your services |
| `status` | `make status` | What's running, health, ports |
| `logs postgres` | `make logs s=postgres` | Follow a service's logs |
| `info` | `make info` | Print URLs, connection strings, passwords |
| `clean` | `make clean` | Stop everything and **delete all data** (asks you to type `delete`) |

No `make` on your machine? Use `./setup.sh` — the commands are identical.

---

## Configuration

Your settings live in **`.env`** at the repo root (created by `setup.sh`, ignored by git). See [`.env.example`](.env.example) for every option.

```bash
# change a port or password, then apply it:
nano .env
./setup.sh up
```

- **`SERVICES`** — what `./setup.sh up` starts.
- **`BIND_IP`** — `127.0.0.1` (default) means only your machine can connect. Set `0.0.0.0` to allow other devices on your network (e.g. testing from a phone).
- **Ports & passwords** — one variable each (`POSTGRES_PORT`, `MYSQL_ROOT_PASSWORD`, `GRAFANA_PORT`, …).

> **Note:** databases store their users on first start. Changing `POSTGRES_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `NEO4J_PASSWORD`, `RABBITMQ_*` or `GRAFANA_ADMIN_*` later won't change an existing install — change it inside the service, or reset that service's data (see [Data](#data--reset)).

The compose files also work on their own, without `setup.sh` — every value has a built-in default:

```bash
cd common-docker-services
docker compose --env-file ../.env up -d postgres redis
```

---

## Connecting from your app

**App running on your machine** — use `localhost` and the ports above:

```env
DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
REDIS_URL=redis://localhost:6379
MONGODB_URI=mongodb://localhost:27017/myapp
SMTP_HOST=localhost
SMTP_PORT=1025
AMQP_URL=amqp://admin:admin@localhost:5672
```

**App running in Docker** — join the shared `app` network and use the service name as the host (`postgres:5432`, `redis:6379`, `mailpit:1025`, …). Add this to your project's `docker-compose.yml`:

```yaml
services:
  api:
    # ...
    networks: [app]

networks:
  app:
    external: true
```

---

## Monitoring

### OpenTelemetry → Jaeger, Prometheus, Grafana (`otel`)

Point any OpenTelemetry SDK at the collector:

```env
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # OTLP/HTTP   (gRPC: localhost:4317)
OTEL_SERVICE_NAME=my-app
```

| Signal | Where it goes | Where to look |
|---|---|---|
| Traces | Collector → Jaeger | http://localhost:16686, or Grafana → Explore → Jaeger |
| Metrics | Collector → Prometheus | http://localhost:9090, or Grafana → Explore → Prometheus |
| Logs | Collector stdout | `./setup.sh logs otel-collector` |

Grafana (http://localhost:4444, `admin` / `admin`) comes with the Prometheus and Jaeger datasources already set up.

To have Prometheus scrape an app that exposes `/metrics`, add a job to [`app-monitoring/otel/prometheus/prometheus.yml`](app-monitoring/otel/prometheus/prometheus.yml) using `host.docker.internal:<port>` as the target (there is a commented example), then `./setup.sh restart`.

### Elasticsearch + Kibana (`elk`)

Single-node Elasticsearch on http://localhost:9200 and Kibana on http://localhost:5601, **without security** (no login, no TLS) to keep local dev simple.

ELK is memory-hungry: Elasticsearch takes ~1 GB and Kibana ~1–1.5 GB while starting. If you run it next to many other services, give Docker at least **6 GB** (Docker Desktop → Settings → Resources). The Elasticsearch heap is `ES_HEAP` in `.env` (default `512m`).

---

## Data & reset

Each service keeps its data in a named Docker volume, so `down`, `up`, restarts, and even updating this repo don't lose anything.

```bash
./setup.sh down                       # stop everything, keep data
./setup.sh clean                      # stop everything and DELETE ALL data (asks first)

# reset just one service, e.g. MySQL:
docker rm -f mysql
docker volume rm common-docker-services_mysql_data
./setup.sh up
```

List the volumes with `docker volume ls | grep -E 'common-docker-services|app-monitoring'`.

---

## Adminer themes

Set `ADMINER_DESIGN` in `.env` (default `flat`), then `./setup.sh up`:

`adminer-dark` · `brade` · `bueltge` · `dracula` · `esterka` · `flat` · `galkaev` · `haeckel` · `hever` · `konya` · `lavender-light` · `lucas-sandery` · `mancave` · `mvt` · `nette` · `ng9` · `nicu` · `pappu687` · `paranoiq` · `pepa-linha` · `pokorny` · `price` · `rmsoft` · `rmsoft_blue` · `rmsoft_blue-dark` · `win98`

---

## Installing Docker manually

`setup.sh` can install Docker for you, but if you'd rather do it yourself:

- **macOS:** [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/) (`brew install --cask docker`), or [OrbStack](https://orbstack.dev/) / [Colima](https://github.com/abiosoft/colima).
- **Windows:** [Docker Desktop with WSL 2](https://docs.docker.com/desktop/features/wsl/), then run `./setup.sh` inside your WSL terminal.
- **Ubuntu / Debian** ([official guide](https://docs.docker.com/engine/install/ubuntu/)):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# use docker without sudo (then log out and back in)
sudo usermod -aG docker $USER
docker run hello-world
```

### Docker cheat sheet

```bash
docker ps                          # running containers   (-a: include stopped)
docker images                      # downloaded images
docker logs -f <container>         # follow logs
docker exec -it <container> sh     # shell inside a container (bash if available)
docker stop|start|restart <container>
docker rm <container>              # remove a stopped container
docker rmi <image>                 # remove an image
docker volume ls                   # list data volumes
docker system df                   # disk usage
docker system prune                # clean up stopped containers, unused networks and dangling images
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| **"Port … is already in use"** | `setup.sh` offers the next free port. You can also set it yourself in `.env`. |
| **Kibana takes minutes to open** | Normal on its first start — it sets up its system indices (3–5 min on a laptop). Later starts are faster. |
| **Kibana / Elasticsearch keeps restarting** | Not enough memory. Give Docker 6 GB+ or run fewer services next to `elk`. |
| **`permission denied … docker.sock`** (Linux) | Your user isn't in the `docker` group yet: run `newgrp docker` or log out and back in. |
| **A changed password doesn't work** | The old one is stored in the data volume — see [Data & reset](#data--reset). |
| **A service is unhealthy** | `./setup.sh logs <service>` shows why. `./setup.sh status` shows health. |
| **Docker isn't running** | `setup.sh` starts Docker Desktop (macOS) or the Docker service (Linux) for you and waits for it. |

---

## Project layout

```text
.
├── setup.sh                         # the one command (menu, config, start, health checks)
├── install.sh                       # curl | bash installer
├── Makefile                         # make shortcuts for setup.sh
├── .env.example                     # every setting with its default
├── common-docker-services/
│   └── docker-compose.yml           # postgres, mysql, mongo, redis, neo4j, adminer, mailpit, rabbitmq, livekit
└── app-monitoring/
    ├── otel/                        # OpenTelemetry Collector, Prometheus, Grafana, Jaeger
    │   ├── docker-compose.yml
    │   ├── collector/config.yml
    │   ├── prometheus/prometheus.yml
    │   └── grafana/provisioning/datasources/datasources.yml
    └── elk/                         # Elasticsearch + Kibana
        ├── docker-compose.yml
        ├── elasticsearch/config/elasticsearch.yml
        └── kibana/config/kibana.yml
```

---

## Security

This is for **local development**. The default passwords are public, and Elasticsearch, MongoDB and Redis run without authentication. Ports only listen on `127.0.0.1` by default. Don't set `BIND_IP=0.0.0.0` on a server reachable from the internet — Docker-published ports bypass firewalls like `ufw`.

## Contributing

Issues and PRs are welcome. CI runs [ShellCheck](https://www.shellcheck.net/) on the scripts, validates every compose file, and does a real `./setup.sh` run.

To add a service: add it to `common-docker-services/docker-compose.yml` (with a `container_name`, a healthcheck and `${VAR:-default}` ports), then register it in `setup.sh` (`ALL_ITEMS`, `CONFIG_SPEC` and the `item_*` functions) and regenerate the example env with `./setup.sh _env-example > .env.example`.

## License

[MIT](LICENSE)
