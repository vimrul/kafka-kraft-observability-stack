#!/usr/bin/env bash
set -euo pipefail

REPO="kafka-kraft-observability-stack"
MON_IP="192.168.1.224"
BROKER_1="192.168.1.100"
BROKER_2="192.168.1.101"
BROKER_3="192.168.1.102"

mkdir -p "$REPO"/{kafka/{configs/jmx,systemd,scripts},monitoring/{prometheus/alerts,alertmanager,grafana/provisioning/{datasources,dashboards},grafana/dashboards},tools}

########## ROOT FILES ##########
cat > "$REPO/.env.example" <<EOF
# ====== Kafka Cluster (KRaft) ======
KAFKA_VERSION=3.7.0
SCALA_VERSION=2.13

# Broker IPs
BROKER_1=$BROKER_1
BROKER_2=$BROKER_2
BROKER_3=$BROKER_3

# Monitoring VM
MON_IP=$MON_IP
EOF

cat > "$REPO/README.md" <<'EOF'
# Kafka KRaft Observability Stack

Production-style starter for a **3-node Apache Kafka 3.7.0 (KRaft)** cluster with **Prometheus, Alertmanager, Grafana, kafka-exporter, node-exporter and JMX exporter**.

## What you get
- Hardened **Kafka systemd unit** + **server.properties template**
- **JMX exporter** config (exposes metrics at `:7071`)
- **Prometheus** scrape configs + **Kafka alert rules**
- **Grafana** provisioning for datasource & dashboards (paste your dashboard JSON in `monitoring/grafana/dashboards/kafka.json`)
- Minimal scripts to install Kafka and enable JMX on each broker

## Network (example)
- Brokers: `192.168.1.221-223`
- Monitoring VM: `192.168.1.224` (Prometheus:9090, Grafana:3000, Alertmanager:9093)

## Quick start
1) **On each broker**: install Kafka + enable JMX (see `kafka/scripts/`), create data/log dirs, set `broker.id` and `listeners`.
2) **On monitoring VM**: `docker compose up -d` inside `monitoring/`.
3) **Grafana** → login → Datasources (Prometheus auto-provisioned) → Dashboards → import/confirm **Kafka** dashboard.

## Security
- Add firewall rules (allow 9092 only from trusted networks; JMX 7071 only from Prometheus VM).
- Add TLS/SASL to Kafka before production.

EOF

########## KAFKA CONFIGS ##########
cat > "$REPO/kafka/configs/server.properties.template" <<'EOF'
# --- Kafka 3.7.0 KRaft server.properties (template) ---
process.roles=broker,controller
node.id=__SET_ME_PER_NODE__
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
advertised.listeners=PLAINTEXT://__THIS_NODE_IP__:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT

log.dirs=/var/lib/kafka/data
metadata.log.dir=/var/lib/kafka/metadata

controller.quorum.voters=1@${BROKER_1}:9093,2@${BROKER_2}:9093,3@${BROKER_3}:9093

num.network.threads=3
num.io.threads=8
num.partitions=3
auto.create.topics.enable=true

# Replication safety
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2

# JMX exporter binds via KAFKA_OPTS (see unit)
EOF

cat > "$REPO/kafka/configs/jmx/kafka.yml" <<'EOF'
lowercaseOutputName: true
lowercaseOutputLabelNames: true
rules:
  - pattern: "kafka.server<type=(.+), name=(.+)PerSec\\w*, topic=(.+)><>Count"
    name: kafka_server_$1_$2_total
    labels: { topic: "$3" }
    type: COUNTER
  - pattern: "kafka.server<type=(.+), name=(.+)><>Value"
    name: kafka_server_$1_$2
    type: GAUGE
  - pattern: "kafka.controller<type=(.+), name=(.+)><>Value"
    name: kafka_controller_$1_$2
    type: GAUGE
  - pattern: "kafka.network<type=(.+), name=(.+)><>Value"
    name: kafka_network_$1_$2
    type: GAUGE
  - pattern: "kafka.network<type=RequestMetrics, name=TotalTimeMs, request=(.+), quantile=(.+)><>Value"
    name: kafka_network_requestmetrics_totaltimems
    labels: { request: "$1", quantile: "$2" }
    type: GAUGE
  - pattern: ".*"
EOF

########## SYSTEMD UNIT ##########
cat > "$REPO/kafka/systemd/kafka.service" <<'EOF'
[Unit]
Description=Apache Kafka 3.7.0 (KRaft mode)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms1G -Xmx1G"
Environment="KAFKA_OPTS=-javaagent:/opt/jmx_prometheus_javaagent.jar=7071:/opt/jmx/kafka.yml -Dcom.sun.management.jmxremote"
ExecStart=/bin/sh -c '/opt/kafka/bin/kafka-server-start.sh /etc/kafka/server.properties'
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=5
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

########## KAFKA SCRIPTS ##########
cat > "$REPO/kafka/scripts/install_kafka_3_7.sh" <<'EOF'
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
EOF
chmod +x "$REPO/kafka/scripts/install_kafka_3_7.sh"

cat > "$REPO/kafka/scripts/enable_jmx.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo mkdir -p /opt/jmx
sudo cp "$(dirname "$0")/../configs/jmx/kafka.yml" /opt/jmx/kafka.yml
sudo curl -fSLo /opt/jmx_prometheus_javaagent.jar \
  https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.20.0/jmx_prometheus_javaagent-0.20.0.jar
sudo chown -R kafka:kafka /opt/jmx /opt/jmx_prometheus_javaagent.jar
echo "Ensure KAFKA_OPTS in systemd unit includes the javaagent line on port 7071."
EOF
chmod +x "$REPO/kafka/scripts/enable_jmx.sh"

########## MONITORING STACK ##########
cat > "$REPO/monitoring/docker-compose.yml" <<EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alerts:/etc/prometheus/alerts:ro
    ports:
      - "9090:9090"
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --web.enable-lifecycle

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro

  kafka-exporter:
    image: danielqsj/kafka-exporter:latest
    container_name: kafka-exporter
    command:
      - --kafka.server=${BROKER_1}:9092
      - --kafka.server=${BROKER_2}:9092
      - --kafka.server=${BROKER_3}:9092
    ports:
      - "9308:9308"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
EOF

cat > "$REPO/monitoring/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alerts/*.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: node-exporter
    static_configs:
      - targets:
          - "${BROKER_1}:9100"
          - "${BROKER_2}:9100"
          - "${BROKER_3}:9100"

  - job_name: kafka-exporter
    static_configs:
      - targets: ["kafka-exporter:9308"]

  - job_name: kafka-brokers-jmx
    static_configs:
      - targets:
          - "${BROKER_1}:7071"
          - "${BROKER_2}:7071"
          - "${BROKER_3}:7071"
EOF

cat > "$REPO/monitoring/prometheus/alerts/kafka.yml" <<'EOF'
groups:
- name: kafka-basic
  rules:
  - alert: KafkaNoActiveController
    expr: sum(kafka_controller_kafkacontroller_activecontrollercount) < 1
    for: 1m
    labels: { severity: critical }
    annotations:
      summary: "No active controller in Kafka cluster"
  - alert: KafkaUnderReplicatedPartitions
    expr: sum(kafka_server_replicamanager_underreplicatedpartitions) > 0
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "Under-replicated partitions > 0"
  - alert: KafkaOfflinePartitions
    expr: sum(kafka_controller_kafkacontroller_offlinepartitionscount) > 0
    for: 2m
    labels: { severity: critical }
    annotations:
      summary: "Offline partitions > 0"
  - alert: KafkaExporterDown
    expr: up{job="kafka-exporter"} == 0
    for: 2m
    labels: { severity: critical }
    annotations:
      summary: "kafka-exporter is down"
EOF

cat > "$REPO/monitoring/alertmanager/alertmanager.yml" <<'EOF'
route:
  receiver: "blackhole"
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 12h

receivers:
  - name: "blackhole"
EOF

cat > "$REPO/monitoring/grafana/provisioning/datasources/datasource.yml" <<EOF
apiVersion: 1
datasources:
  - name: prometheus
    type: prometheus
    access: proxy
    url: http://${MON_IP}:9090
    isDefault: true
EOF

cat > "$REPO/monitoring/grafana/provisioning/dashboards/dashboard.yml" <<'EOF'
apiVersion: 1
providers:
  - name: 'kafka-dashboards'
    orgId: 1
    folder: ''
    type: file
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
EOF

cat > "$REPO/monitoring/grafana/dashboards/kafka.json" <<'EOF'
{
  "annotations":{"list":[]},
  "editable": true,
  "fiscalYearStartMonth": 1,
  "graphTooltip": 0,
  "panels": [],
  "refresh": "30s",
  "schemaVersion": 36,
  "style": "dark",
  "tags": ["kafka","kraft","prometheus"],
  "templating": {"list":[]},
  "time": {"from":"now-1h","to":"now"},
  "title": "Kafka (placeholder)",
  "version": 1
}
EOF

########## TOOLS ##########
cat > "$REPO/tools/node-exporter.service" <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > "$REPO/tools/start_node_exporter.sh" <<'EOF'
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
EOF
chmod +x "$REPO/tools/start_node_exporter.sh"

echo "✅ Scaffold created at ./$REPO"
