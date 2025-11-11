# Kafka KRaft Observability Stack

This repository provides a complete, production-grade setup for a **3-node Apache Kafka 3.7.0 (KRaft mode)** cluster with full observability using **Prometheus**, **Grafana**, **Alertmanager**, and **Kafka Exporter**.

It’s designed for DevOps engineers who want to deploy, monitor, and maintain a highly available Kafka cluster with end-to-end visibility into brokers, partitions, and system metrics.

---

## 🚀 Features

* **Kafka 3.7.0 (KRaft mode)** — No ZooKeeper required
* **3-node cluster** for leader election and high availability
* **JMX Exporter** for per-broker metrics
* **Prometheus** for data collection
* **Grafana** for visualization
* **Alertmanager** for alerting
* **Kafka Exporter** for consumer lag monitoring
* **Node Exporter** for server-level metrics

---

## 🧱 Architecture Overview

```
Kafka01 ─┐                ┌── Prometheus ──> Grafana (Dashboards)
Kafka02 ─┼─> 9092/7071 ─> │
Kafka03 ─┘                └── Alertmanager + Kafka Exporter
```

| Node    | Role       | IP            | Services                                          |
| ------- | ---------- | ------------- | ------------------------------------------------- |
| kafka01 | Broker 1   | 192.168.1.221 | Kafka, JMX Exporter, Node Exporter                |
| kafka02 | Broker 2   | 192.168.1.222 | Kafka, JMX Exporter, Node Exporter                |
| kafka03 | Broker 3   | 192.168.1.223 | Kafka, JMX Exporter, Node Exporter                |
| kafka04 | Monitoring | 192.168.1.224 | Prometheus, Grafana, Alertmanager, Kafka Exporter |

---

## ⚙️ Prerequisites

* **Ubuntu 22.04 LTS** or similar
* Java 17+ installed (`openjdk-17-jdk`)
* Docker + Docker Compose (for monitoring VM)
* Passwordless SSH (optional for automation)
* Ports open: 9092, 7071, 9100, 9090, 3000, 9093, 9308

---

## 🪶 Step 1 — Clone Repository

```bash
git clone https://github.com/yourusername/kafka-kraft-observability-stack.git
cd kafka-kraft-observability-stack
```

---

## 🧩 Step 2 — Install Kafka (on all 3 brokers)

```bash
cd kafka/scripts
sudo bash install_kafka_3_7.sh
```

This will:

* Create the `kafka` user
* Download and extract Kafka 3.7.0
* Create all required directories
* Download JMX Prometheus agent

---

## 🧩 Step 3 — Configure Each Broker

Edit `/etc/kafka/server.properties`:

```bash
sudo nano /etc/kafka/server.properties
```

### Example per node:

**kafka01:**

```
node.id=1
advertised.listeners=PLAINTEXT://192.168.1.221:9092
```

**kafka02:**

```
node.id=2
advertised.listeners=PLAINTEXT://192.168.1.222:9092
```

**kafka03:**

```
node.id=3
advertised.listeners=PLAINTEXT://192.168.1.223:9092
```

Ensure these are common across all nodes:

```
process.roles=broker,controller
controller.listener.names=CONTROLLER
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
controller.quorum.voters=1@192.168.1.221:9093,2@192.168.1.222:9093,3@192.168.1.223:9093
```

---

## 🧩 Step 4 — Configure systemd Unit

```bash
sudo cp kafka/systemd/kafka.service /etc/systemd/system/kafka.service
sudo systemctl daemon-reload
sudo systemctl enable --now kafka
```

Check status:

```bash
sudo systemctl status kafka -l
```

If successful, verify metrics endpoint:

```bash
curl -s http://localhost:7071/metrics | head
```

---

## 🧩 Step 5 — Initialize the Cluster

Run only once from any broker:

```bash
/opt/kafka/bin/kafka-storage.sh random-uuid
sudo -u kafka /opt/kafka/bin/kafka-storage.sh format \
  -t <uuid> \
  -c /etc/kafka/server.properties
```

---

## 🧩 Step 6 — Setup Monitoring VM

### Install Docker + Compose

```bash
sudo apt update -y
sudo apt install -y docker.io docker-compose
```

### Start Monitoring Stack

```bash
cd monitoring
sudo docker compose up -d
```

Check containers:

```bash
docker ps
```

Visit:

* Prometheus: [http://192.168.1.224:9090](http://192.168.1.224:9090)
* Grafana: [http://192.168.1.224:3000](http://192.168.1.224:3000)
* Alertmanager: [http://192.168.1.224:9093](http://192.168.1.224:9093)

---

## 📈 Step 7 — Verify Prometheus Targets

Visit `http://192.168.1.224:9090/targets` and ensure:

* kafka-brokers-jmx — UP
* kafka-exporter — UP
* node-exporter — UP

---

## 📊 Step 8 — Import Grafana Dashboard

Login Grafana:

```
User: admin
Password: admin
```

Then navigate to:
**Dashboards → Import → Upload File →** `monitoring/grafana/dashboards/kafka.json`

You’ll now see broker, topic, and consumer lag metrics in real time.

---

## ⚠️ Step 9 — Verify Alerts

Check active alerts:

```
http://192.168.1.224:9090/alerts
```

Try stopping a Kafka broker to see alerts for:

* Offline partitions
* No active controller
* Under-replicated partitions

---

## 🧭 Step 10 — Install Node Exporter (on brokers)

```bash
cd tools
sudo bash start_node_exporter.sh
```

Verify:

```bash
curl -s http://localhost:9100/metrics | head
```

---

## 🧰 Useful Kafka Commands

**Describe cluster status:**

```bash
/opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server 192.168.1.221:9092 describe --status
```

**List topics:**

```bash
/opt/kafka/bin/kafka-topics.sh --bootstrap-server 192.168.1.221:9092 --list
```

**Produce messages:**

```bash
/opt/kafka/bin/kafka-console-producer.sh --broker-list 192.168.1.221:9092 --topic test.topic
```

**Consume messages:**

```bash
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server 192.168.1.221:9092 --topic test.topic --from-beginning
```

---

## ✅ Verification Checklist

| Component     | Check      | Command                  |
| ------------- | ---------- | ------------------------ |
| Kafka         | Active     | `systemctl status kafka` |
| JMX Exporter  | Working    | `curl :7071/metrics`     |
| Prometheus    | Healthy    | `curl :9090/-/healthy`   |
| Grafana       | Accessible | `:3000`                  |
| Node Exporter | Running    | `curl :9100/metrics`     |

---

## 🧠 How It Works

* Kafka exposes metrics through JMX Exporter (`7071`)
* Prometheus scrapes all metrics every 15s
* Grafana visualizes real-time broker data
* Alertmanager handles cluster health alerts
* Kafka Exporter reports consumer group lag

---

## 🧾 Troubleshooting

* **Kafka not starting:** Check `/var/log/kafka` or `journalctl -u kafka -xe`
* **Prometheus no data:** Verify `prometheus.yml` targets and firewall
* **Grafana empty panels:** Check datasource URL and Prometheus connection
* **Alertmanager not firing:** Validate alert rules under `monitoring/prometheus/alerts/`

---

## 🏁 Cleanup

```bash
cd monitoring
sudo docker compose down -v
sudo systemctl disable --now kafka
```

---

## 📜 License

MIT License — free to use, modify, and deploy.

---

**Repository:** kafka-kraft-observability-stack
**Author:** Mohammad Imrul Hasan
**Role:** DevOps & DevSecOps Engineer

