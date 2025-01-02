#!/bin/bash   

# Detect the platform (similar to $OSTYPE)
OSTYPE=$(uname -m)
if [[ $OSTYPE =~ ^x86_64 ]]; then
  PROMETHEUS_VERSION="2.44.0"
  echo "Installing Prometheus for Architecture : $OSTYPE"
  sudo useradd --no-create-home --shell /bin/false prometheus
  sudo useradd --no-create-home --shell /bin/false node_exporter
  sudo groupadd prometheus
  sudo usermod -a -G prometheus prometheus
  sudo mkdir /etc/prometheus
  sudo mkdir /var/lib/prometheus
  sudo chown prometheus:prometheus /etc/prometheus
  sudo chown prometheus:prometheus /var/lib/prometheus
  sudo wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && sudo tar zxvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz && sudo cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/ && sudo cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
  sudo chown prometheus:prometheus /usr/local/bin/prometheus
  sudo chown prometheus:prometheus /usr/local/bin/promtool
  sudo cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus
  sudo cp -r prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus
  sudo chown -R prometheus:prometheus /etc/prometheus/consoles
  sudo chown -R prometheus:prometheus /etc/prometheus/console_libraries
  sudo rm -fr prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz prometheus-${PROMETHEUS_VERSION}.linux-amd64
  cat <<-EOF | sudo tee /etc/prometheus/prometheus.yml >/dev/null
---
global:
  scrape_interval: 15s
  evaluation_interval: 15s
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093
rule_files:
  - rules/rules.yml
  - rules/selfmonitoring-exporter.yml
  - rules/asterisk_alert.yml
  - rules/blackbox.yml
  - rules/mysqld-exporter-rules.yml
  - rules/nginx-exporter-rules.yml
scrape_configs:
  - job_name: prometheus
    metrics_path: /prometheus/metrics
    static_configs:
      - targets:
          - localhost:9090
        labels:
          instance: falcon
  - job_name: alertmanager
    static_configs:
      - targets:
          - localhost:9093
  - job_name: mysql
    static_configs:
      - targets:
          - localhost:9104
        labels:
          instance: falcon
  - job_name: nginx-monitoring
    static_configs:
      - targets:
          - falcon:9113
    relabel_configs:
      - source_labels:
          - __address__
        separator: ":"
        regex: (.*):(.*)
        replacement: ${1}
        target_label: instance
  - job_name: phonepe_dc
    static_configs:
      - targets:
          - localhost:9100
        labels:
          instance: prometheus
      - targets:
          - jarvis:9100
        labels:
          instance: jarvis
  - job_name: phonepe-udial-application-status
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
         - http://sparta:8717/ping
         - http://sparta:8719/UDialerIvr/action/test
         - http://app_node_1:6695/ping
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:8099
  - job_name: Bot-prod-app-endpoints
    metrics_path: /probe
    params:
      module: [ tcp_connect ] # Look for a HTTP 200 response.
    static_configs:
      - targets:
        - phoenix:6483
        - phoenix:6658
        - phoenix:6697
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:8099

EOF
  sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
  cat <<-EOF | sudo tee /etc/systemd/system/prometheus.service >/dev/null
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus \\
  --web.console.templates=/etc/prometheus/consoles \\
  --web.console.libraries=/etc/prometheus/console_libraries \\
  --storage.tsdb.retention.time=30d
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=always

[Install]
WantedBy=default.target
EOF

  sudo chown -R root:root /etc/systemd/system/prometheus.service
  sleep 5
else
  exit
fi

# shellcheck disable=SC2039
if [[ $OSTYPE =~ ^x86_64 ]]; then
  # Install Node Exporter
  NODE_EXPORTER_VERSION="1.6.0"
  echo "Installing Node exporter for Architecture : $OSTYPE"
  sudo groupadd node_exporter
  sudo usermod -a -G node_exporter node_exporter
  sudo useradd --no-create-home --shell /bin/false node_exporter
  sudo wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
  sudo tar zxvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
  sudo cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter
  sudo rm -fr node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64
else
  exit
fi
sudo chown -R node_exporter:node_exporter /usr/local/bin/node_exporter
cat <<-EOF | sudo tee /etc/systemd/system/node_exporter.service >/dev/null
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo chown -R root:root /etc/systemd/system/node_exporter.service
sudo chmod 755 /usr/local/bin/node_exporter

service="$(sudo systemctl is-active node_exporter)"
if [ "$service" = "active" ]; then
  sudo systemctl enable node_exporter
  echo "Node exporter has been successfully installed on instance."
  response=$(curl --write-out '%{http_code}' --silent --output /dev/null http://localhost:9100/metrics)
  if [ "$response" -ne 200 ]; then
    echo "Node exporter has started exposing metrics on port:9100 to scrapping service."
  else
    echo "Issue querying node exporter metrics"
  fi
else
  echo "Service not running.... so trying to restart"
fi

# Installing Grafana on Monitoring Server

# Install Grafana
GRAFANA_VERSION="9.5.0"
sudo useradd --no-create-home --shell /bin/false grafana
sudo groupadd grafana
sudo usermod -a -G grafana grafana
wget https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz
tar -xvf grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz
sudo mv grafana-${GRAFANA_VERSION} /etc/grafana
sudo chown grafana:grafana /etc/grafana

cat <<-EOF | sudo tee /etc/systemd/system/grafana.service >/dev/null
[Unit]
Description=Grafana
Wants=network-online.target
After=network-online.target

[Service]
User=grafana
Group=grafana
ExecStart=/etc/grafana/bin/grafana-server --homepath /etc/grafana
Restart=on-failure

[Install]
WantedBy=default.target

EOF
sudo chown -R root:root /etc/systemd/system/grafana.service

# Install Alert Manager on Monitoring Server
# Create a user and group for Alertmanager:
ALERTMANAGER_VERSION="0.25.0"
sudo useradd --no-create-home --shell /bin/false alertmanager
sudo groupadd alertmanager
sudo usermod -a -G alertmanager alertmanager
#Download and install the Alertmanager binaries:
sudo wget  https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
sudo tar -xvf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
sudo cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager /usr/local/bin/
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager
sudo mkdir -p /etc/alertmanager
sudo cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager.yml /etc/alertmanager
sudo chown -R alertmanager:alertmanager /etc/alertmanager
sudo mkdir -p /var/lib/alertmanager
sudo chown alertmanager:alertmanager /var/lib/alertmanager
#Create a systemd unit for Alertmanager
cat <<-EOF | sudo tee /etc/systemd/system/alertmanager.service >/dev/null
[Unit]
Description=Prometheus Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
--config.file /etc/alertmanager/alertmanager.yml \
--storage.path /var/lib/alertmanager/

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo rm -fr alertmanager-${ALERTMANAGER_VERSION}.linux-amd64 alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz grafana-9.5.0.linux-amd64.tar.gz
# Start Prometheus, Grafana, Alertmanager, and Node Exporter

echo "Starting Prometheus, Grafana, Alertmanager, and Node Exporter services..."

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

sudo systemctl enable grafana
sudo systemctl start grafana

sudo systemctl enable alertmanager
sudo systemctl start alertmanager

sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "Prometheus, Grafana, Alertmanager, and Node Exporter installation completed."

sudo systemctl status prometheus.service
sudo systemctl status alertmanager.service
sudo systemctl status grafana.service
sudo systemctl status node_exporter.service
#################

# sudo systemctl status alertmanager.service  -- Listens on Port : 9093
# sudo systemctl status prometheus.service    -- Listens on Port : 9090
# sudo systemctl status grafana-server.service  -- Listens on Port : 3000
# sudo systemctl status node_exporter.service   -- Listens on Port : 9100
