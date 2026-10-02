#!/usr/bin/env bash
# One-time host setup: installs the INDI vendor udev rules (from the built image) plus
# local device-symlink rules, so cameras get the large USB buffer and stable /dev names.
# Run after `make build`:  sudo ./host/install-host.sh
set -euo pipefail

IMAGE="${IMAGE:-indi-controller:latest}"
RULES_DIR=/etc/udev/rules.d
HERE="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "Image $IMAGE not found; run 'make build' first"; exit 1; }

echo "Installing INDI vendor udev rules from $IMAGE..."
container=$(docker create "$IMAGE")
trap 'docker rm -f "$container" >/dev/null' EXIT
tmp=$(mktemp -d)
docker cp "$container:/lib/udev/rules.d/." "$tmp/"
for rule in "$tmp"/99-*.rules; do
    name=$(basename "$rule")
    [[ "$name" == "99-systemd.rules" ]] && continue   # belongs to systemd, not INDI
    install -m 0644 "$rule" "$RULES_DIR/$name"
    echo "  $name"
done
rm -rf "$tmp"

echo "Installing local device rules..."
for rule in "$HERE"/udev/*.rules; do
    install -m 0644 "$rule" "$RULES_DIR/$(basename "$rule")"
    echo "  $(basename "$rule")"
done

udevadm control --reload-rules
udevadm trigger
echo "Done. Replug USB devices (or reboot) for the rules to take effect."
