# Kafka KRaft Observability Stack

A Linux-based reference setup for a **three-node Apache Kafka 3.7.0 KRaft cluster**, with broker, consumer, and host metrics collected by Prometheus and visualized in Grafana.

The project brings cluster configuration, systemd services, exporters, dashboards, and operational checks together so an engineer can follow the path from a running broker to a useful monitoring signal.

**Scope:** this is an adaptable reference environment. The checked-in defaults are not a hardened production deployment, and no throughput, availability, or recovery-time benchmark is claimed.

## Engineering focus

- Configure three combined broker/controller nodes without ZooKeeper.
- Manage Kafka and host exporters as Linux services.
- Separate broker/JVM metrics, consumer-group metrics, and host metrics.
- Verify cluster state and metrics before trusting dashboards or alerts.
- Document the dependencies and failure checks that an operator needs.

## Architecture

```text
Applications --> Kafka brokers 1, 2, 3 :9092
                    | KRaft controller quorum :9093
                    |
                    +--> JMX exporter on each broker :7071 ---+
                    +--> Node exporter on each host :9100 ---+--> Prometheus :9090
                    +<-- Kafka exporter :9308 ---------------+       |
                                                                   Grafana :3000

Prometheus --[configure alerting target]--> Alertmanager :9093
                                           |
                                           +--[configure receiver]--> notification
```

The monitoring services run on a separate host from the brokers. The controller listener and Alertmanager both use port 9093 on their respective hosts.

## Repository map

| Path | Purpose |
| --- | --- |
| [kafka/scripts/](kafka/scripts/) | Kafka installation and JMX agent configuration |
| [server.properties.template](kafka/configs/server.properties.template) | Per-node broker/controller configuration |
| [kafka.service](kafka/systemd/kafka.service) | Kafka systemd unit and JVM agent options |
| [monitoring/docker-compose.yml](monitoring/docker-compose.yml) | Prometheus, Grafana, Alertmanager, and Kafka Exporter |
| [monitoring/prometheus/](monitoring/prometheus/) | Scrape targets and example alert rules |
| [monitoring/grafana/](monitoring/grafana/) | Datasource/dashboard provisioning and dashboard JSON |
| [tools/](tools/) | Node Exporter installer and service unit |

## Before setup

Use disposable Linux lab hosts with Java 17, curl, tar, systemd, and administrative access. The monitoring host needs Docker Engine and the Compose plugin. The Node Exporter helper downloads a Linux amd64 binary; adapt it for another architecture.

Example addresses are `192.168.1.100`, `.101`, and `.102` for brokers and `.103` for monitoring. Replace them consistently in the Kafka configuration, Compose Kafka Exporter arguments, and Prometheus targets. Permit required traffic only between the relevant hosts.

## Setup sequence

Run repository-relative commands below from the repository root unless a different directory is shown.

### 1. Obtain the files on each broker

```bash
git clone https://github.com/vimrul/kafka-kraft-observability-stack.git
cd kafka-kraft-observability-stack
sudo bash kafka/scripts/install_kafka_3_7.sh
sudo cp kafka/configs/server.properties.template /etc/kafka/server.properties
sudo bash kafka/scripts/enable_jmx.sh
```

The second script installs the JMX mapping file required by the systemd unit. The installer alone does not copy that file or finish broker configuration.

### 2. Configure each broker before starting it

Edit `/etc/kafka/server.properties`:

- Assign unique `node.id` values 1, 2, and 3.
- Replace `__THIS_NODE_IP__` with that node's reachable address.
- Replace every `${BROKER_1}`, `${BROKER_2}`, and `${BROKER_3}` placeholder with a real address; the template is not rendered automatically.
- Keep the same `controller.quorum.voters` mapping on all nodes.

For example, the shared quorum line is:

```properties
controller.quorum.voters=1@192.168.1.100:9093,2@192.168.1.101:9093,3@192.168.1.102:9093
```

### 3. Initialize new storage with one shared cluster ID

Generate a cluster ID once:

```bash
/opt/kafka/bin/kafka-storage.sh random-uuid
```

Record it and use the **same value on each of the three nodes**, formatting each node's new storage before starting Kafka:

```bash
sudo -u kafka /opt/kafka/bin/kafka-storage.sh format \
  -t 'REPLACE_WITH_THE_SHARED_CLUSTER_ID' \
  -c /etc/kafka/server.properties
```

Formatting is initial setup, not a recovery action for an existing cluster. Do not reformat existing data to troubleshoot a failed service.

### 4. Start the broker and inspect its metrics

```bash
sudo cp kafka/systemd/kafka.service /etc/systemd/system/kafka.service
sudo systemctl daemon-reload
sudo systemctl enable --now kafka
sudo systemctl status kafka --no-pager
curl -fsS http://localhost:7071/metrics
```

Install Node Exporter using an absolute script path because the helper changes its working directory:

```bash
sudo bash "$PWD/tools/start_node_exporter.sh"
curl -fsS http://localhost:9100/metrics
```

### 5. Configure and start monitoring

On the monitoring host, obtain the same repository and review:

1. Broker addresses in `monitoring/docker-compose.yml`.
2. JMX and host targets in `monitoring/prometheus/prometheus.yml`.
3. The Grafana datasource URL in `monitoring/grafana/provisioning/datasources/datasource.yml`. For this Compose network, use `http://prometheus:9090` instead of the checked-in placeholder.
4. Grafana credentials, container versions, network exposure, and persistent storage appropriate to your environment.

```bash
cd monitoring
docker compose config --quiet
docker compose up -d
docker compose ps
```

Grafana's provisioning mounts the included dashboard directory. Verify the datasource and panels after startup; an empty panel is not evidence of zero failures.

### 6. Complete notification wiring

The supplied Prometheus file has alert rules but **does not configure an Alertmanager target**. Add an `alerting` section to its configuration:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]
```

The supplied Alertmanager receiver is named `blackhole` and has no notification integration. Configure a real receiver separately, keep its credentials outside Git, and validate delivery. Prometheus showing a firing alert does not prove an email or chat notification was sent.

## Validation and recovery exercise

These are checks to run in your environment, not recorded test results.

| Check | Evidence to collect |
| --- | --- |
| KRaft quorum | Cluster ID, leader, and current voter information |
| Scrape targets | JMX, Kafka Exporter, and Node Exporter targets are UP in Prometheus |
| Dashboard | Queries return metrics matching your installed exporter versions |
| Notifications | A controlled test reaches the configured destination |
| Broker interruption | A replicated test topic remains usable with the expected ISR behavior |
| Broker return | The restarted broker rejoins and replicas catch up |

Useful inspection commands:

```bash
/opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server 192.168.1.100:9092 describe --status
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server 192.168.1.100:9092 --describe
journalctl -u kafka -n 100 --no-pager
```

For a lab failover exercise, first verify a healthy quorum and a test topic with replication factor 3 and suitable minimum ISR settings. Stop only one broker, record client behavior and monitoring signals, then restart it and confirm recovery before another experiment. Preserve data and investigate logs if it does not rejoin.

## Operational boundaries

- Kafka listeners are plaintext; authentication, TLS, authorization, and network controls require design for the target environment.
- The combined broker/controller layout is a reference topology, not a capacity or isolation recommendation.
- Monitoring images use `latest`, and durable monitoring storage is not configured explicitly.
- The Grafana example uses default credentials. Node Exporter runs as root in the supplied service.
- Example alert metric names must be checked against the installed JMX mapping and Kafka version.
- Existing alert rules do not cover every missing-target or missing-metric condition.
- User-topic replication and minimum ISR need explicit review; internal-topic settings do not establish every user topic's durability policy.
- This repository does not implement backup, automated disaster recovery, or an upgrade strategy.

To stop the monitoring services without intentionally deleting volumes, run `docker compose down` from `monitoring/`. Protect Kafka data directories and any required monitoring data before cleanup.

Author: [Mohammad Imrul Hasan](https://imrul.net/). For Kafka configuration and storage behavior, consult the [Apache Kafka documentation](https://kafka.apache.org/documentation/).
