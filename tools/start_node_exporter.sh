#!/usr/bin/env bash
set -euo pipefail
VER=1.8.2
cd /tmp
curl -fSLo node_exporter.tar.gz \
  https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz
tar -xzf node_exporter.tar.gz
sudo mv node_exporter-${VER}.linux-amd64/node_exporter /usr/local/bin/
sudo mv /etc/systemd/system/node-exporter.service /etc/systemd/system/node-exporter.service.bak 2>/dev/null || true
sudo cp "$(dirname "$0")/node-exporter.service" /etc/systemd/system/node-exporter.service
sudo systemctl daemon-reload
sudo systemctl enable --now node-exporter
