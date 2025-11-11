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

