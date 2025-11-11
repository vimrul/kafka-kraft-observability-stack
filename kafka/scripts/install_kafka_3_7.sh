#!/usr/bin/env bash
set -euo pipefail
KAFKA_VERSION="${KAFKA_VERSION:-3.7.0}"
SCALA_VERSION="${SCALA_VERSION:-2.13}"

id -u kafka &>/dev/null || sudo useradd -r -m -d /home/kafka -s /bin/bash kafka
sudo mkdir -p /opt /etc/kafka /var/lib/kafka/{data,metadata} /var/log/kafka /opt/jmx
cd /opt
if [ ! -f "kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" ]; then
  curl -fSLo kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz \
  "https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
fi
sudo tar -xzf kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz
sudo ln -sfn kafka_${SCALA_VERSION}-${KAFKA_VERSION} kafka

curl -fSLo /opt/jmx_prometheus_javaagent.jar \
  https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.20.0/jmx_prometheus_javaagent-0.20.0.jar

sudo chown -R kafka:kafka /opt/kafka* /etc/kafka /var/lib/kafka /var/log/kafka /opt/jmx /opt/jmx_prometheus_javaagent.jar

echo "Copy server.properties.template to /etc/kafka/server.properties and adjust node.id + advertised.listeners."
echo "Then: sudo systemctl enable --now kafka"
