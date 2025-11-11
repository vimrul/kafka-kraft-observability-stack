Kafka KRaft Observability Stack

This repository provides a complete, production-style setup for a 3-node Apache Kafka 3.7.0 (KRaft mode) cluster with integrated Prometheus, Grafana, Alertmanager, Kafka Exporter, and Node Exporter monitoring.

It’s ideal for DevOps engineers who want to deploy and monitor a distributed Kafka cluster with visibility into brokers, partitions, replication health, and system metrics.

⸻

🚀 Features
	•	Kafka in KRaft mode (no Zookeeper)
	•	3-node cluster configuration for resilience and leader election
	•	JMX Exporter integration for per-broker metrics
	•	Prometheus for metrics collection
	•	Grafana for dashboards and visualizations
	•	Alertmanager for basic alert routing
	•	Kafka Exporter for consumer lag and topic metrics
	•	Node Exporter for system-level monitoring

⸻

🧱 Architecture Overview

Kafka01 ─┐                ┌── Prometheus ──> Grafana
Kafka02 ─┼─> 9092/7071 ─> │
Kafka03 ─┘                └── Alertmanager

Each Kafka node runs:
	•	kafka-server-start.sh with JMX agent at :7071
	•	Exposes metrics to Prometheus running on the Monitoring VM

Monitoring VM hosts:
	•	Prometheus (9090)
	•	Grafana (3000)
	•	Alertmanager (9093)
	•	Kafka Exporter (9308)

⸻

⚙️ Prerequisites
	•	4 VMs total (3 Kafka brokers + 1 monitoring VM)
	•	OS: Ubuntu 22.04 LTS or compatible
	•	User: kafka (for Kafka service)
	•	Ports open:
	•	Kafka: 9092, 9093
	•	JMX: 7071
	•	Node Exporter: 9100
	•	Monitoring VM: 9090, 3000, 9093, 9308

⸻

🪶 Step 1: Clone Repository

git clone https://github.com/your-username/kafka-kraft-observability-stack.git
cd kafka-kraft-observability-stack


⸻

🧩 Step 2: Install Kafka (on all 3 brokers)

cd kafka/scripts
sudo bash install_kafka_3_7.sh

This script will:
	•	Create kafka user
	•	Download and extract Kafka 3.7.0
	•	Create necessary directories
	•	Download JMX Prometheus agent

⸻

🧩 Step 3: Configure each Broker

Edit /etc/kafka/server.properties

sudo nano /etc/kafka/server.properties

Set unique values on each node:

Node 1 (Kafka01)

node.id=1
advertised.listeners=PLAINTEXT://192.168.1.221:9092

Node 2 (Kafka02)

node.id=2
advertised.listeners=PLAINTEXT://192.168.1.222:9092

Node 3 (Kafka03)

node.id=3
advertised.listeners=PLAINTEXT://192.168.1.223:9092

Keep other settings from kafka/configs/server.properties.template.

⸻

🧩 Step 4: Configure systemd Unit

sudo cp kafka/systemd/kafka.service /etc/systemd/system/kafka.service
sudo systemctl daemon-reload
sudo systemctl enable --now kafka

Check status:

sudo systemctl status kafka -l

Check logs:

journalctl -u kafka -n 100 --no-pager


⸻

🧩 Step 5: Enable JMX Exporter

Each broker exposes metrics on port 7071:

curl -s http://localhost:7071/metrics | head

If metrics appear, Prometheus can scrape them.

⸻

📦 Step 6: Setup Monitoring VM

Install Docker + Docker Compose

sudo apt update
sudo apt install -y docker.io docker-compose

Launch the stack

cd monitoring
sudo docker compose up -d

This runs:
	•	Prometheus on 9090
	•	Alertmanager on 9093
	•	Grafana on 3000
	•	Kafka Exporter on 9308

Check containers:

docker ps


⸻

📈 Step 7: Verify Prometheus Targets

Visit:

http://192.168.1.224:9090/targets

All targets (kafka-brokers-jmx, kafka-exporter, node-exporter) should show UP.

⸻

📊 Step 8: Configure Grafana

Open Grafana in your browser:

http://192.168.1.224:3000

Default credentials:

User: admin
Password: admin

Go to Dashboards → Import → Upload JSON → select monitoring/grafana/dashboards/kafka.json.

Your Kafka metrics (topics, partitions, replication, controller health, consumer lag, etc.) should appear within a minute.

⸻

⚠️ Step 9: Test Alerts

Open Prometheus:

http://192.168.1.224:9090/alerts

Trigger alerts by stopping a Kafka broker temporarily.

⸻

🧭 Step 10: Node Exporter on Brokers

cd tools
sudo bash start_node_exporter.sh

This will install Node Exporter (port 9100) and register it as a systemd service.

Check:

curl localhost:9100/metrics | head


⸻

✅ Verification Checklist

Component	Check	Command
Kafka Service	Running	systemctl status kafka
JMX Metrics	Exposed	curl :7071/metrics
Prometheus	Active	curl :9090/-/healthy
Grafana	Accessible	http://MON_IP:3000
Node Exporter	Active	curl :9100/metrics


⸻

🧰 Useful Commands

Describe cluster quorum:

/opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server 192.168.1.221:9092 describe --status

List topics:

/opt/kafka/bin/kafka-topics.sh --bootstrap-server 192.168.1.221:9092 --list

Produce messages:

/opt/kafka/bin/kafka-console-producer.sh --broker-list 192.168.1.221:9092 --topic test.topic

Consume messages:

/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server 192.168.1.221:9092 --topic test.topic --from-beginning


⸻

🧠 How It Works
	•	JMX Exporter exposes broker metrics on port 7071.
	•	Prometheus scrapes these metrics every 15 seconds.
	•	Grafana visualizes Prometheus data using dashboards.
	•	Kafka Exporter provides consumer lag & topic data.
	•	Alertmanager triggers notifications for cluster anomalies.

⸻

🧩 Example Alerts

Alert	Condition	Severity
KafkaNoActiveController	activecontrollercount < 1	Critical
KafkaUnderReplicatedPartitions	underreplicatedpartitions > 0	Warning
KafkaOfflinePartitions	offlinepartitionscount > 0	Critical
KafkaExporterDown	up{job="kafka-exporter"} == 0	Critical


⸻

🧾 Troubleshooting

No metrics in Grafana:
	•	Check Prometheus targets page.
	•	Ensure firewall allows 7071, 9308, and 9100 ports.

Kafka service restarting repeatedly:
	•	Verify JMX config file /opt/jmx/kafka.yml syntax.
	•	Check journal logs: journalctl -u kafka -xe

Prometheus not scraping:
	•	Check Prometheus log output: docker logs prometheus

⸻

🏁 Cleanup

cd monitoring
sudo docker compose down -v
sudo systemctl disable --now kafka


⸻

💡 Credits

Built with ❤️ by DevOps engineers for Kafka monitoring enthusiasts.

⸻

Repository: kafka-kraft-observability-stack

License: MIT