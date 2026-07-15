# chromium-selkies-cdp

[![Docker publish](https://github.com/sandlong/chromium-selkies-cdp/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/sandlong/chromium-selkies-cdp/actions/workflows/docker-publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A very thin downstream image built on top of `lscr.io/linuxserver/chromium`, with one optional extra: enable Chromium CDP and forward it to port `9222` when requested.

## What changed from upstream

The base image stays `linuxserver/chromium`. This repository only adds `socat`, a tiny startup wrapper, and a small root init that prepares the CDP profile directory.

When `ENABLE_CDP=true`:

- A root-side `init-cdp-profile` step creates `CDP_PROFILE_DIR` / `CDP_LOG_DIR` and chowns them to `abc` **before** Chromium starts. This means a host bind mount path can be created automatically by Docker (root-owned) and still work without a manual `mkdir`/`chown` on the host.
- Chromium is started with a dedicated profile directory so Chrome 136+ remote debugging rules are satisfied.
- Chromium listens for DevTools on loopback inside the container.
- `socat` forwards container port `9222` to that internal loopback-only DevTools port.

When `ENABLE_CDP=false`:

- The container behaves like normal `linuxserver/chromium`.
- No CDP listener is started.

## One-shot docker run (no pre-created host folders)

As root on the host, this is enough. Docker will create the bind path; the image fixes ownership for `abc` at boot:

```bash
docker rm -f chromium 2>/dev/null || true
rm -rf /root/chromium

docker run -d \
  --name chromium \
  --restart unless-stopped \
  --security-opt seccomp=unconfined \
  --shm-size=8g \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Singapore \
  -e CUSTOM_USER= \
  -e PASSWORD='change-me' \
  -e NO_DECOR=1 \
  -e GOOGLE_API_KEY='your-api-key' \
  -e GOOGLE_DEFAULT_CLIENT_ID='your-client-id.apps.googleusercontent.com' \
  -e GOOGLE_DEFAULT_CLIENT_SECRET='your-client-secret' \
  -e ENABLE_CDP=true \
  -e CDP_PORT=9222 \
  -e CDP_PROFILE_DIR=/config/cdp-profile \
  -p 3000:3000 \
  -p 3001:3001 \
  -p 9222:9222 \
  -v /root/chromium/config:/config \
  ghcr.io/sandlong/chromium-selkies-cdp:latest
```

Important:

- Use **one** volume only: `-v /host/path:/config`. Do **not** also bind a nested path onto `/config/cdp-profile`.
- `PUID`/`PGID` should match a normal host user (e.g. `1000`). Do not use `0`.
- You do **not** need `mkdir`/`chown` on the host first when using this image's `init-cdp-profile`.

Open the browser UI at `https://localhost:3001/`.

Check CDP with:

```bash
curl http://127.0.0.1:9222/json/version
```

## Docker Compose

```yaml
services:
  chromium-selkies-cdp:
    image: ghcr.io/sandlong/chromium-selkies-cdp:latest
    ports:
      - "3001:3001"
      - "9222:9222"
    environment:
      TZ: Asia/Singapore
      CUSTOM_USER: change-me
      PASSWORD: change-me
      ENABLE_CDP: "true"
    volumes:
      - chromium-config:/config
    restart: unless-stopped

volumes:
  chromium-config:
```

Named volumes also work; the same single-`/config` rule applies.

## Environment variables added by this repo

| Variable | Default | Meaning |
| --- | --- | --- |
| `ENABLE_CDP` | `false` | Enable CDP and port `9222` forwarding |
| `CDP_PORT` | `9222` | External forwarded CDP port |
| `CDP_INTERNAL_PORT` | `9223` | Internal loopback CDP port used by Chromium |
| `CDP_PROFILE_DIR` | `/config/cdp-profile` | Profile path used when CDP is enabled |
| `CDP_LOG_DIR` | `/config/log` | Log directory for the `socat` forwarder |

## Important upstream variables you will still use

| Variable | Meaning |
| --- | --- |
| `CUSTOM_USER` / `PASSWORD` | Basic auth for the web UI |
| `CHROME_CLI` | Extra Chromium flags passed through unchanged |
| `TZ` | Timezone |
| `PUID` / `PGID` | Host UID/GID mapped to container user `abc` |
| `SELKIES_MANUAL_WIDTH` / `SELKIES_MANUAL_HEIGHT` | Display size |
| `PIXELFLUX_WAYLAND` | Upstream Wayland toggle |

## Notes

This repo intentionally does not fork or reimplement the upstream desktop stack. It only layers a CDP-on-demand wrapper on top of `linuxserver/chromium` so upstream updates remain easy to track.

CDP access is effectively full browser control. Do not expose port `9222` directly to the public internet.
