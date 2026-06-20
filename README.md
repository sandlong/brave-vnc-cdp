# chromium-selkies-cdp

[![Docker publish](https://github.com/sandlong/chromium-selkies-cdp/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/sandlong/chromium-selkies-cdp/actions/workflows/docker-publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A very thin downstream image built on top of `lscr.io/linuxserver/chromium`, with one optional extra: enable Chromium CDP and forward it to port `9222` when requested.

## What changed from upstream

The base image stays `linuxserver/chromium`. This repository only adds `socat` plus a tiny startup wrapper.

When `ENABLE_CDP=true`:

- Chromium is started with a dedicated profile directory so Chrome 136+ remote debugging rules are satisfied.
- Chromium listens for DevTools on loopback inside the container.
- `socat` forwards container port `9222` to that internal loopback-only DevTools port.

When `ENABLE_CDP=false`:

- The container behaves like normal `linuxserver/chromium`.
- No CDP listener is started.

## Quick start

### Docker Compose

```yaml
services:
  chromium-selkies-cdp:
    image: ghcr.io/sandlong/chromium-selkies-cdp:latest
    ports:
      - "3001:3001"
      - "127.0.0.1:9222:9222"   # localhost-only; CDP is full browser control
    environment:
      TZ: Asia/Singapore
      CUSTOM_USER: change-me
      PASSWORD: change-me
      ENABLE_CDP: "true"
      CDP_BIND_ADDRESS: "0.0.0.0"  # required inside container for Docker port mapping
    volumes:
      - chromium-config:/config
    restart: unless-stopped

volumes:
  chromium-config:
```

Open the browser UI at `https://localhost:3001/`.

Check CDP with:

```bash
curl http://127.0.0.1:9222/json/version
```

For local automation clients that accept direct discovery, `ws://localhost:9222` is the intended endpoint.

### Docker run

```bash
docker run -d \
  --name chromium-selkies-cdp \
  -p 3001:3001 \
  -p 127.0.0.1:9222:9222 \
  -e TZ=Asia/Singapore \
  -e CUSTOM_USER=change-me \
  -e PASSWORD=change-me \
  -e ENABLE_CDP=true \
  -e CDP_BIND_ADDRESS=0.0.0.0 \
  -v chromium-config:/config \
  ghcr.io/sandlong/chromium-selkies-cdp:latest
```

## Environment variables added by this repo

| Variable | Default | Meaning |
| --- | --- | --- |
| `ENABLE_CDP` | `false` | Enable CDP and port `9222` forwarding |
| `CDP_PORT` | `9222` | External forwarded CDP port |
| `CDP_INTERNAL_PORT` | `9223` | Internal loopback CDP port used by Chromium |
| `CDP_BIND_ADDRESS` | `127.0.0.1` | Address socat binds to inside the container. Set to `0.0.0.0` when using Docker port mapping; keep `127.0.0.1` for host-network mode |
| `CDP_PROFILE_DIR` | `/config/cdp-profile` | Profile path used when CDP is enabled |
| `CDP_LOG_DIR` | `/config/log` | Log directory for the `socat` forwarder |

## Important upstream variables you will still use

| Variable | Meaning |
| --- | --- |
| `CUSTOM_USER` / `PASSWORD` | Basic auth for the web UI |
| `CHROME_CLI` | Extra Chromium flags passed through unchanged |
| `TZ` | Timezone |
| `SELKIES_MANUAL_WIDTH` / `SELKIES_MANUAL_HEIGHT` | Display size |
| `PIXELFLUX_WAYLAND` | Upstream Wayland toggle |

## Security

**CDP = full browser control.** Anyone who can reach port `9222` can read cookies, inject JavaScript, and navigate to arbitrary URLs. Harden accordingly:

- Always bind the CDP host port to `127.0.0.1` (as shown in the examples above) unless you explicitly need remote access.
- If remote access is required, put a reverse proxy with authentication (e.g. mTLS, basic-auth, or a VPN) in front of port `9222`.
- Never expose `9222` directly to the public internet.
- The startup script validates `CDP_PORT`, `CDP_INTERNAL_PORT`, and `CDP_BIND_ADDRESS` at boot and will refuse to start if values are malformed.

## Notes

This repo intentionally does not fork or reimplement the upstream desktop stack. It only layers a CDP-on-demand wrapper on top of `linuxserver/chromium` so upstream updates remain easy to track.
