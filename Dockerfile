FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    socat \
    x11vnc \
    xvfb \
    openbox \
    novnc \
    websockify \
    xauth \
    xdg-utils \
    procps \
    dbus-x11 \
    fonts-liberation \
    fonts-noto-color-emoji \
    fonts-noto-cjk \
    libasound2 \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libxdamage1 \
    libxrandr2 \
    libxss1 \
    libxtst6 \
    wget \
 && mkdir -p /usr/share/keyrings \
 && curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
 && curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends brave-browser \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data/profile /var/log/brave-vnc-cdp

COPY scripts/start-brave-vnc-cdp.sh /usr/local/bin/start-brave-vnc-cdp.sh
RUN chmod +x /usr/local/bin/start-brave-vnc-cdp.sh

EXPOSE 8080 5900 9222
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:${CDP_PORT:-9222}/json/version >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/start-brave-vnc-cdp.sh"]
