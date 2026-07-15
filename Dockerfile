FROM lscr.io/linuxserver/chromium:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends socat \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && if [ -f /usr/bin/wrapped-chromium ]; then \
      cp -a /usr/bin/wrapped-chromium /usr/bin/wrapped-chromium.real; \
    fi

COPY root/ /

RUN chmod +x \
    /usr/local/bin/start-cdp-chromium.sh \
    /usr/bin/wrapped-chromium \
    /defaults/autostart \
    /defaults/autostart_wayland \
    /etc/s6-overlay/s6-rc.d/init-cdp-profile/run
