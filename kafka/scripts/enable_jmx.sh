#!/usr/bin/env bash
set -euo pipefail
sudo mkdir -p /opt/jmx
sudo cp "$(dirname "$0")/../configs/jmx/kafka.yml" /opt/jmx/kafka.yml
sudo curl -fSLo /opt/jmx_prometheus_javaagent.jar \
  https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.20.0/jmx_prometheus_javaagent-0.20.0.jar
sudo chown -R kafka:kafka /opt/jmx /opt/jmx_prometheus_javaagent.jar
echo "Ensure KAFKA_OPTS in systemd unit includes the javaagent line on port 7071."
