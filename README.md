# headscale-deploy

English | [简体中文](README.zh-CN.md)

Template-driven Headscale deployment helper for Docker.

This repository is designed for two use cases:

- self-hosters who want a clean Headscale install/upgrade/manage workflow
- people who want to upload a whole directory to a server and use it directly

The project keeps templates, runtime files, and shell logic separated so the code stays maintainable.

## What It Does

- deploys Headscale with the official container image
- renders `config.yaml` and `compose.yaml` from external templates
- supports both interactive install and non-interactive install
- keeps runtime state inside the project
- provides a unified command entrypoint for install, manage, upgrade, repair, and uninstall
- supports optional embedded DERP with explicit modes for:
  - `disabled`
  - `private`
  - `public`

## Project Layout

```text
headscale-deploy/
├─ bin/
│  └─ hsctl
├─ lib/
│  ├─ common.sh
│  ├─ state.sh
│  ├─ validate.sh
│  ├─ render.sh
│  ├─ install.sh
│  ├─ manage.sh
│  ├─ upgrade.sh
│  ├─ repair.sh
│  └─ legacy.sh
├─ templates/
│  ├─ config.yaml.tpl
│  ├─ compose.network.yaml.tpl
│  ├─ compose.portmap.yaml.tpl
│  └─ install.env.example
├─ tests/
│  ├─ validate-local.sh
│  └─ validate-docker.sh
├─ runtime/
│  └─ instance/
└─ headscale-install.sh
```

## Requirements

- Linux
- `bash`
- Docker Engine
- Docker Compose v2 plugin
- root privileges for install/upgrade/repair/uninstall workflows

This project does not install Docker for you.

## Verified Setup

- validated locally against `ghcr.io/juanfont/headscale:0.28.0`
- local safety and render checks are covered by `bash tests/validate-local.sh`
- real Docker lifecycle validation is covered by `sudo -E bash tests/validate-docker.sh`
- current design target is one managed instance per repository checkout

## Quick Start

### 1. Copy the example config

```bash
cp templates/install.env.example runtime/install.env
```

### 2. Edit your deployment settings

At minimum, review:

- `HS_ROOT`
- `SERVER_URL`
- `DOCKER_MODE`
- `HS_DOCKER_NETWORK`
- `HEADSCALE_TAG`
- `DERP_MODE`

`runtime/install.env` uses simple `KEY=value` syntax with optional single or double quotes. Values are parsed as data only, not executed as shell code. If a value contains spaces, wrap it in quotes.

### 3. Render files first

```bash
bash bin/hsctl render --auto --config runtime/install.env
```

This creates:

- `runtime/instance/config/config.yaml`
- `runtime/instance/compose.yaml`

### 4. Install

```bash
bash bin/hsctl install --auto --config runtime/install.env
```

## Validation

Before publishing changes, run:

```bash
bash tests/validate-local.sh
```

If you have a Docker-enabled Linux host available, also run:

```bash
sudo -E bash tests/validate-docker.sh
```

The Docker validation script uses temporary state files and a temporary install root under `/tmp`, so it does not touch the default `runtime/` instance.

## Commands

```bash
bash bin/hsctl install [--auto] [--config FILE]
bash bin/hsctl render [--auto] [--config FILE]
bash bin/hsctl up
bash bin/hsctl down
bash bin/hsctl status
bash bin/hsctl logs

bash bin/hsctl user add NAME
bash bin/hsctl user delete NAME
bash bin/hsctl user list

bash bin/hsctl node list [--user NAME]
bash bin/hsctl node register --user NAME --key NODEKEY
bash bin/hsctl node delete ID

bash bin/hsctl key create --user NAME
bash bin/hsctl key list

bash bin/hsctl apikey create [--expiration DURATION]
bash bin/hsctl apikey list
bash bin/hsctl apikey expire --prefix PREFIX

bash bin/hsctl upgrade [--image-tag TAG] [--no-backup]
bash bin/hsctl repair db
bash bin/hsctl uninstall [-y]
```

## Install Modes

### Interactive

```bash
bash bin/hsctl install
```

Good for first-time manual setup.

### Non-interactive

```bash
bash bin/hsctl install --auto --config runtime/install.env
```

Good for repeatable deployments and automation.

## Docker Modes

### `DOCKER_MODE=network`

Use this when Headscale sits behind a reverse proxy such as Traefik.

Behavior:

- no host TCP port is published for Headscale itself
- the container joins an external Docker network
- the reverse proxy should route HTTPS traffic to the `headscale` container
- if embedded DERP is enabled, the compose file also publishes `3478/udp`

### `DOCKER_MODE=portmap`

Use this when you want to expose Headscale directly from the host.

Behavior:

- publishes `${PORT}:8080`
- if embedded DERP is enabled, also publishes `${DERP_STUN_PORT}/udp`

## DERP Modes

### `DERP_MODE=disabled`

Default and safest.

- embedded DERP server stays off
- clients continue to use upstream DERP map entries

### `DERP_MODE=private`

Recommended for personal use or team-only deployments.

- embedded DERP server is enabled
- `verify_clients: true`
- only valid clients from your Headscale environment should be able to relay through it
- much lower abuse risk than public mode

This is the right default if you want a China mainland node for your own tailnet without offering public relay bandwidth.

### `DERP_MODE=public`

Only use this intentionally.

- embedded DERP server is enabled
- `verify_clients: false`
- unknown clients are no longer rejected at the DERP verification layer
- this creates real relay bandwidth exposure

Important:

- setting `public` does not automatically make the whole internet use your DERP
- clients still need a DERP map that contains your region
- but once your region is published and verification is disabled, traffic risk becomes real

## DERP Risk Model

If you are deploying for self-use, the key risk control is:

```text
DERP_MODE=private
```

That gives you:

- embedded DERP enabled
- client verification enabled
- your own Headscale users can benefit
- random outside usage is much harder

If you want to switch to a public or community relay model later, change:

```text
DERP_MODE=public
```

and then intentionally publish your DERP region to the clients you want to serve.

In other words:

- `private` = self-use friendly
- `public` = bandwidth donation / public-service posture

## Recommended Settings For China Mainland Deployment

If your server is in mainland China, a practical starting point is:

```bash
DOCKER_MODE=network
SERVER_URL="https://<your-headscale-domain>"
DERP_MODE=private
DERP_IPV4=your.public.ip
DERP_STUN_LISTEN_ADDR=0.0.0.0:3478
DERP_INCLUDE_DEFAULTS=true
```

And make sure:

- your domain resolves correctly
- HTTPS reverse proxy is working
- `3478/udp` is open in the firewall/security group
- your reverse proxy forwards HTTPS traffic to Headscale

Why this is the safer choice:

- your own users can prefer a nearby DERP region
- you still keep the upstream DERP map as fallback
- you do not immediately open the relay to arbitrary users

## Example Non-interactive Install

```bash
bash bin/hsctl install --auto \
  --config runtime/install.env \
  --serverurl "https://<your-headscale-domain>" \
  --docker-network headscale \
  --derp-mode private \
  --derp-ipv4 203.0.113.10
```

## Legacy Compatibility

The old flat script interface is still available:

```bash
bash headscale-install.sh --listusers
bash headscale-install.sh --upgrade --image-tag 0.28.0
```

Internally it is now a compatibility wrapper around `bin/hsctl`.

## Notes

- runtime state is stored in `runtime/state.env`
- generated files live under `runtime/instance/`
- the install flow writes state only after a successful startup
- config rendering is template-based, so future options are easier to add
- one repository checkout manages one active instance at a time
- install output prints an initial pre-auth key; treat it as sensitive

## Extra Docs

- [Chinese client onboarding guide](docs/CLIENT_ONBOARDING.zh-CN.md)
- [GitHub publishing guide (Chinese)](docs/GITHUB_PUBLISHING.zh-CN.md)

## Roadmap

- policy file template support
- optional PostgreSQL template support
- clearer reverse proxy examples
- more complete DERP public-service guidance
