# brave-vnc-cdp

A Docker image for **Brave Browser + noVNC + raw VNC + Chrome DevTools Protocol (CDP)**, intended for local browser automation on **Linux arm64/aarch64** as well as amd64.

This project exists for one practical reason: cloud browser providers are useful, but sometimes you want a **real local browser** that:

- exposes a CDP endpoint on `9222`
- can be watched live through **noVNC**
- works well with agent frameworks such as **OpenClaw** and **Hermes Agent**
- can run on **ARM64 servers**
- uses **Brave** instead of plain Chromium

## What it provides

- Official **Brave Browser** installed from Brave's Linux APT repository
- **Xvfb** virtual display for headed browsing inside a container
- **Openbox** lightweight desktop session
- **x11vnc** server on port `5900`
- **noVNC** web client on port `8080`
- **CDP** endpoint on port `9222`
- Persistent browser profile storage in `/data/profile`

## Why Brave instead of Chromium

Brave is Chromium-based, so it works with CDP clients just like Chrome or Chromium, but it also brings Brave-specific features such as Shields. That can be convenient for interactive browsing, though it may change page behavior for some automation flows. If a site breaks, tune Brave settings for that site or pass extra launch flags through `BRAVE_ARGS`.

## Quick start

### Docker run

```bash
docker build -t brave-vnc-cdp .

docker run -d \
  --name brave-vnc-cdp \
  -p 8080:8080 \
  -p 5900:5900 \
  -p 9222:9222 \
  -e TZ=Asia/Singapore \
  -e VNC_PASS='change-me-now' \
  -e START_URL='https://example.com' \
  -v brave-data:/data \
  brave-vnc-cdp
```

### Docker Compose

```bash
docker compose up -d --build
```

Then open:

- noVNC: `http://127.0.0.1:8080/vnc.html`
- raw VNC: `127.0.0.1:5900`
- CDP JSON: `http://127.0.0.1:9222/json/version`

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `TZ` | `UTC` | Container timezone |
| `VNC_PASS` | `change-me` | Password for x11vnc |
| `VNC_WIDTH` | `1440` | Virtual display width |
| `VNC_HEIGHT` | `900` | Virtual display height |
| `VNC_DEPTH` | `24` | Color depth |
| `VNC_PORT` | `5900` | Raw VNC port |
| `WEB_PORT` | `8080` | noVNC/websockify port |
| `CDP_PORT` | `9222` | Chrome DevTools Protocol port |
| `BRAVE_INTERNAL_CDP_PORT` | `9223` | Internal loopback CDP port used by Brave itself |
| `VNC_SHARED` | `false` | Allow multiple VNC viewers |
| `START_URL` | `about:blank` | Initial page to open |
| `USER_DATA_DIR` | `/data/profile` | Persistent Brave profile path |
| `BRAVE_NO_SANDBOX` | `true` | Add `--no-sandbox` inside container |
| `BRAVE_ARGS` | empty | Extra Brave flags as a single string |

## CDP usage

After the container starts, inspect the browser endpoint:

```bash
curl http://127.0.0.1:9222/json/version
```

You should see a `webSocketDebuggerUrl` that CDP clients can connect to.

Internally, Brave binds CDP to loopback. The container forwards that internal port back out to `0.0.0.0:${CDP_PORT}` so host tools can still attach normally.

## OpenClaw example

See `examples/openclaw.browser.json5`.

Typical config:

```json5
{
  browser: {
    enabled: true,
    defaultProfile: "brave-local",
    profiles: {
      brave-local: {
        cdpUrl: "http://127.0.0.1:9222",
        color: "#FB542B"
      }
    }
  }
}
```

## Hermes Agent example

See `examples/hermes-browser.md`.

Typical flow:

```text
/browser connect ws://127.0.0.1:9222/devtools/browser/<id>
```

Depending on Hermes version, `ws://127.0.0.1:9222` may also work if it performs endpoint discovery for you.

## Important operational note

If **OpenClaw** and **Hermes** attach to the same browser instance at the same time, they can interfere with each other by fighting over tabs, focus, and page state. For shared use, prefer one active controller at a time, or run separate container instances.

## Security notes

- Change `VNC_PASS` before exposing this beyond localhost.
- Prefer binding ports to localhost or a private tailnet.
- CDP is powerful. Anyone who reaches it can effectively control the browser.
- If you publish this behind a reverse proxy, add authentication in front of noVNC.

## Logs

Runtime logs are written inside the container under:

- `/var/log/brave-vnc-cdp/xvfb.log`
- `/var/log/brave-vnc-cdp/openbox.log`
- `/var/log/brave-vnc-cdp/x11vnc.log`
- `/var/log/brave-vnc-cdp/novnc.log`
- `/var/log/brave-vnc-cdp/brave.log`

## Roadmap ideas

- Non-root runtime user
- Optional `supervisord`/s6 management
- Built-in health/status page
- Multi-arch GHCR publish workflow
- Optional auth in front of noVNC
