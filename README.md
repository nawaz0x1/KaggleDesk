# KaggleDesk (Xfce + noVNC + Cloudflare Tunnel)

A full Linux desktop running **inside this container**, reachable from any browser
at a public `https://…trycloudflare.com` URL. No VNC client, no port forwarding,
no Docker required.

Verified working in this Kaggle container: Ubuntu 24.04, Xfce 4.18, 1600×900,
VNC-password authentication over a Cloudflare quick tunnel.

---

## Quick start

```bash
bash /kaggle/working/KaggleDesk/setup.sh     # first time: install everything and start
bash /kaggle/working/KaggleDesk/start.sh     # later: just start it again
bash /kaggle/working/KaggleDesk/stop.sh      # stop desktop + tunnel
```

`start.sh` prints something like:

```
  Desktop    : https://<random-words>.trycloudflare.com/vnc.html
  One-click  : https://<random-words>.trycloudflare.com/vnc.html?autoconnect=1&resize=scale&path=websockify&password=<pw>
  Password   : <pw>
  Local      : http://127.0.0.1:6080/vnc.html
```

The URL is also saved to `url.txt` and the password to `vnc_password.txt`.

---

## Using it

- **One-click link** (`autoconnect=1&password=…`): opens straight into the desktop.
- **Plain link** (`/vnc.html`): asks for the password, shows more options.
- Put `resize=scale` (already in the one-click link) to make the desktop fit your
  window; remove it for a fixed 1600×900 canvas with scrollbars.
- Works on phones/tablets too — pinch-zoom the page, the desktop scales.

If the page loads but the screen stays black, reload; a quick tunnel occasionally
drops the first WebSocket.

---

## Architecture

```
browser ──https/wss──► Cloudflare edge ──tunnel──► cloudflared (this container)
                                                     │
                                                     ▼
                                   websockify :6080  ──►  Xtigervnc :5901
                                   (serves noVNC,          (X server + Xfce)
                                    bridges WS→VNC)
```

| Component | Role | Binding |
|---|---|---|
| `Xtigervnc :1` | Virtual X server, Xfce session, VNC auth | `127.0.0.1:5901` |
| `websockify` | Serves noVNC HTML/JS and proxies WebSocket ↔ TCP | `127.0.0.1:6080` |
| `cloudflared` | Quick tunnel, public HTTPS/WSS ingress | outbound only |

Nothing but the tunnel is exposed to the internet; VNC and noVNC listen on
loopback only.

---

## Files

| File | Purpose |
|---|---|
| `setup.sh` | Install apt/pip dependencies, then call `start.sh` |
| `start.sh` | Start VNC + websockify + tunnel, print URL and password (idempotent) |
| `stop.sh` | Stop tunnel, websockify and the X server |
| `vncpw.py` | Writes the TigerVNC password file (VNC DES obfuscation) |
| `vnc_password.txt` | Desktop password (8 chars are used, the rest is cosmetic) |
| `url.txt` | Last public URL |
| `vnc.log`, `websockify.log`, `cf.log` | Per-component logs |
| `desktop.png` | Screenshot of the live desktop |

Generated at runtime (not in this repo): `/root/.vnc/passwd`,
`/root/.vnc/xstartup`, `/root/.vnc/*.log`, `*.pid`.

---

## Configuration

`start.sh` reads these environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `GEOMETRY` | `1600x900` | Screen resolution |
| `VNC_PORT` | `5901` | Loopback VNC port |
| `WEB_PORT` | `6080` | Loopback noVNC port |
| `DISPLAY_NUM` | `:1` | X display number |

```bash
GEOMETRY=1920x1080 bash /kaggle/working/KaggleDesk/start.sh
```

To change resolution after it is already running: `bash stop.sh` then start with
the new `GEOMETRY`.

---

## Adding software

```bash
apt-get install -y --no-install-recommends gimp inkscape epiphany-browser
```

New Xfce applications appear under **Applications** in the top-left panel menu.
`epiphany-browser` (GNOME Web) is the easiest real browser on Ubuntu 24.04 —
Firefox/Chromium are snap-only there and snap does not work in this container.

Command-line tools installed with `pip`/`apt` are usable from `xfce4-terminal`
inside the desktop, and see the same filesystem as this notebook
(`/kaggle/working`, `/kaggle/input`, …).

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `vnc.html` loads, desktop never appears | Tunnel dropped the WebSocket: reload the page, or `bash start.sh` again. Check `cf.log`. |
| "Failed to connect to server" | VNC/websockify not running: `bash start.sh`, then check `vnc.log`. |
| Everything disconnects after repeated attempts | TigerVNC blacklists the client IP after failed logins. `start.sh` sets `-BlacklistThreshold 10000`; if it still happens, `bash stop.sh && bash start.sh`. |
| Cloudflare error 1033 / "tunnel not found" | Quick tunnel expired. Restart it: `bash stop.sh && bash start.sh` (new URL). |
| URL works for me but not for someone else | Quick tunnels are rate-limited and short-lived; for anything lasting, use a named tunnel (below). |
| Sluggish mouse/typing | Quick tunnels add latency. Lower `GEOMETRY`, or use `--protocol quic` instead of `http2` in `start.sh`. |
| Session ended, nothing responds | Kaggle stopped the container. Re-run `start.sh`; you get a new URL, same password. |
| Forgot the password | `cat vnc_password.txt` (or delete it and re-run `start.sh` to generate a new one). |

Logs: `tail -f /kaggle/working/KaggleDesk/{vnc,websockify,cf}.log`

---

## Security

- The tunnel URL is public. The **only** gate is the VNC password, and anyone
  past it gets a **root shell** in this container, with access to
  `/kaggle/working` and any mounted data.
- Treat the one-click link (it contains the password) as a secret. Do not paste
  it into chats, notebooks, or commits.
- `vnc_password.txt` is plaintext on disk; rotate it by deleting the file and
  re-running `start.sh`.
- Stop the tunnel when you are done: `bash stop.sh`.

---

## Why not Docker?

`docker`/`dockerd` cannot run here: the container has the default capability set
(`CapEff: 0x00000000a80425fb`), so no `CAP_SYS_ADMIN`, no `/var/run/docker.sock`
and no privileged mode. `dockerd`/`runc` need those to create namespaces and
mount overlayfs, so inner containers are impossible.

What this setup does instead is install the desktop **in the container you already
have** — which is itself a Docker container, so the isolation story is the same
and the performance is far better.

If you specifically need image-level isolation, `udocker` (PRoot mode) can run
OCI images without privileges, but a desktop inside it is very slow. Rootless
podman also fails here for the same capability reasons.

---

## Stable URL (optional)

Quick tunnels get a random hostname on each start. For a permanent one:

```bash
cloudflared tunnel login                    # browser auth, needs a Cloudflare zone
cloudflared tunnel create kaggle-desktop
cloudflared tunnel route dns kaggle-desktop desktop.example.com
```

Then run it with a config file instead of `--url`:

```yaml
# ~/.cloudflared/config.yml
tunnel: kaggle-desktop
credentials-file: /root/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: desktop.example.com
    service: http://127.0.0.1:6080
  - service: http_status:404
```

```bash
cloudflared tunnel run kaggle-desktop
```

---

## Notes / limits

- Everything dies with the Kaggle session; only files under `/kaggle/working`
  survive. `start.sh` is all you need after a restart.
- No GPU acceleration, no audio, no clipboard sync (noVNC clipboard is text-only
  and works through the sidebar).
- The container is 4 vCPU / ~31 GB RAM; Xfce itself uses well under 1 GB.

---

## Reuse outside Kaggle

The scripts are plain bash and assume nothing Kaggle-specific — just **root +
apt + outbound HTTPS**:

- any Debian/Ubuntu container (Google Colab, RunPod, Vast.ai, Lambda, a dev
  container, LXC, …)
- a VPS or bare-metal Ubuntu 22.04/24.04 (run `setup.sh` directly)
- a WSL2 Ubuntu instance (`cloudflared` then gives you a public URL too)

```bash
unzip linux-desktop-browser.zip
cd linux-desktop-in-browser
bash setup.sh
```

Differences worth knowing on other hosts:

- On a normal server you do not need the tunnel: `start.sh` always binds noVNC to
  `127.0.0.1`, so either forward it (`ssh -L 6080:127.0.0.1:6080 user@host`) or
  change `127.0.0.1:$WEB_PORT` in `start.sh` to `0.0.0.0:$WEB_PORT` and put
  nginx/TLS in front. VNC itself stays on loopback either way.
- On Colab the container is already root and `apt-get` works, but `/content`
  is the persistent volume — run `bash /content/setup.sh` from there.
- If `cloudflared` is not installed, install it first:
  `curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared`
- `vnc_password.txt` is **not** shipped in the archive; the first `start.sh`
  run generates a fresh password.
