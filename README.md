# INDI_Controller

A containerized INDI server (plus optional headless PHD2) that runs on any Linux machine
connected to your astronomy hardware. You run KStars/Ekos on another computer
(Windows, macOS, or Linux) and connect to it over the network.

```
 KStars/Ekos (Windows / macOS / Linux)
        │  TCP 7624 (INDI)   TCP 4400 (PHD2)
        ▼
 ┌──────────────────────────────┐
 │ indi-controller container    │
 │  indiserver + drivers        │──USB/serial──▶ mount, cameras, focuser, ...
 │  PHD2 on Xvfb (optional)     │
 │  INDI Web Manager (optional) │
 └──────────────────────────────┘
```

## Requirements

- Linux host on x86_64 (the image is Ubuntu 26.04 with the INDI and PHD2 PPAs)
- Docker Engine with the Compose plugin
- Hardware plugged into this host by USB

## Quick start

```bash
git clone <this repo> INDI_Controller && cd INDI_Controller
make env          # creates .env (defaults to simulator drivers)
make build
sudo make host-setup   # udev rules: USB buffer size, permissions, /dev symlinks
make up
make logs
```

To try the full chain before connecting real hardware, leave `INDI_DRIVERS` set to the
simulators and connect Ekos to them.

## Configuration (`.env`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `INDI_MODE` | `static` | `static`: start `indiserver` with `INDI_DRIVERS` at boot. `webmanager`: start INDI Web Manager and choose drivers from Ekos or `http://<host>:8624` |
| `INDI_DRIVERS` | simulators | Space-separated driver binaries (`make drivers` lists them) |
| `INDI_VERBOSE` | `false` | Pass `-v` to `indiserver` |
| `INDI_AUTOCONNECT` | `true` | `static` mode: connect every device at startup, without waiting for a client |
| `INDI_AUTOCONNECT_TIMEOUT` | `300` | Seconds to keep retrying devices that haven't connected yet (late USB enumeration, mount powered on later) |
| `ENABLE_PHD2` | `true` | Run PHD2 headless on port 4400 |
| `INSTALL_PHD2` | `true` | Build-time; `false` leaves PHD2 out of the image |
| `INDI_HOST_PORT` / `INDI_WEB_HOST_PORT` / `PHD2_HOST_PORT` | 7624 / 8624 / 4400 | Host-side ports |

After you edit `.env`, run `make restart`.

State is stored in `./config` (mounted at `/config`, which is the container's `$HOME`):
INDI driver settings (`.indi/`), Web Manager profiles, and PHD2 settings and logs. Back up
this directory to move a configured setup to another machine.

### Choosing a mode

- **static** (recommended): the driver set is fixed in `.env`, so the server is identical
  on every boot. In the Ekos profile, leave **INDI Web Manager unchecked**.
- **webmanager**: Ekos starts and stops drivers itself through the Web Manager. This is
  useful when one machine serves different rigs. In the Ekos profile, **check** INDI Web
  Manager (port 8624). You can also mark a profile *autostart* in the web UI.

## Connecting from KStars/Ekos

1. Install KStars from https://kstars.kde.org. No INDI drivers are needed on the client.
2. In Ekos, open the **Profile Editor** and create a new profile:
   - Mode: **Remote**. Host: the controller's IP. Port: `7624`.
   - Select the same devices you listed in `INDI_DRIVERS`.
   - Set **INDI Web Manager** as described in [Choosing a mode](#choosing-a-mode).
3. **Guiding:** in the Guide module, choose PHD2 with host set to the controller IP and
   port `4400`. If you set `ENABLE_PHD2=false`, use the internal guider instead.
4. **Plate solving:** install ASTAP and a star database (for example D50) on the
   *client*, then select the local solver in the Align module.
5. **Capture upload mode:** **Client** sends frames to the Ekos machine over the
   network. A full ASI183 frame is about 40 MB, so use a wired LAN if you can.

## Hardware notes

- The container runs `privileged` with `/dev` mounted, so devices plugged in after
  startup are visible to it.
- `host-setup` copies the INDI vendor udev rules out of the image onto the host. Among
  other things, this raises `usbfs_memory_mb` for ZWO cameras; without that, large
  frames fail to download. It also installs `host/udev/99-zz-local-astronomy.rules`.
  Edit that file to give each device a stable symlink (for example `/dev/cgem_mount`),
  then point the driver's port setting at the symlink.
- If a device works on the host but not in the container, check `lsusb` on the host,
  then run `make shell` and `ls -l /dev/<device>` inside the container.

## Security

INDI and PHD2 have **no authentication**. Anyone who can reach these ports can move the
mount. Expose them only on a trusted LAN or a VPN such as Tailscale, and never
port-forward them on your router.

## Commands

Run `make help` to see every target. The common ones are `build`, `up`, `down`,
`restart`, `logs`, `shell`, `drivers`, `status`, and `host-setup`.
