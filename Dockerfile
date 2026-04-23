FROM lscr.io/linuxserver/chromium:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends socat \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY root/ /

RUN chmod +x \
    /usr/local/bin/start-cdp-chromium.sh \
    /defaults/autostart \
    /defaults/autostart_wayland
