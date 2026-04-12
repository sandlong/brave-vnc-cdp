Hermes can attach to the local Brave CDP endpoint exposed by this container.

Typical flow:

1. Start the container and confirm CDP is live:

   curl http://127.0.0.1:9222/json/version

2. In Hermes CLI:

   /browser connect ws://127.0.0.1:9222/devtools/browser/<id>

   or, if Hermes supports the shorthand discovery flow in your version:

   /browser connect ws://127.0.0.1:9222

3. Open noVNC in a browser to watch the live session:

   http://127.0.0.1:8080/vnc.html

Important: if Hermes and OpenClaw both attach to the same browser at the same time,
page focus and tab state can interfere with each other. Prefer one active controller
at a time, or run separate container instances.
