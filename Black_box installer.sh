#/bin/bash
#-    author          Narendra Babu
########################################
#----#
# Install Blackbox Exporter

echo "Installing Prometheus..."
sudo useradd -M -r -s /bin/false blackbox
sudo groupadd blackbox
sudo usermod -a -G blackbox blackbox
wget -q "https://github.com/prometheus/blackbox_exporter/releases/download/v0.24.0/blackbox_exporter-0.24.0.linux-amd64.tar.gz"
tar -xzf "blackbox_exporter-0.24.0.linux-amd64.tar.gz"
cd "blackbox_exporter-0.24.0.linux-amd64/" || exit
sudo mv blackbox_exporter /usr/local/bin
sudo mkdir -p /etc/blackbox
sudo mv blackbox.yml /etc/blackbox
sudo chown blackbox:blackbox /usr/local/bin/blackbox_exporter
sudo chown -R blackbox:blackbox /etc/blackbox/*
sudo chown -R blackbox:blackbox /etc/blackbox

# Configure BlackBox service
echo "Configuring BlackBox service..."
sudo tee /etc/systemd/system/blackbox.service > /dev/null << EOF
[Unit]
Description=Blackbox
Wants=network-online.target
After=network-online.target

[Service]
User=blackbox
Group=blackbox
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter \
  --config.file /etc/blackbox/blackbox.yml \
  --web.listen-address 0.0.0.0:8099

Restart=always

[Install]
WantedBy=multi-user.target

EOF

sudo bash -c 'cat > /etc/prometheus/rules/blackbox.yml' << EOF
groups:
- name: alert.rules
  rules:
  - alert: EndpointDown
    expr: probe_success == 0
    for: 10m
    annotations:
      title: "Endpoint {{ \$labels.instance }} is DOWN"
      description: '{{ \$labels.instance }} has been down for more than 10 minutes.'
      runbook_url: https://ubona.atlassian.net/l/cp/P1Xjscw1
      dashboard_url: https://monitoring.ubona.com/goto/3PCisyTSR?orgId=2
    labels:
      severity: 'CRITICAL'

  - alert: HTTPProbeFailure
    # Blackbox probe HTTP failure
    expr: probe_http_status_code <= 199 OR probe_http_status_code >= 400
    for: 5m
    labels:
      severity: 'CRITICAL'
    annotations:
      title: 'Probes are failing with non-HTTP response'
      runbook_url: https://ubona.atlassian.net/l/cp/450a4xNW
      dashboard_url: https://monitoring.ubona.com/goto/-Oq4ssoIR?orgId=2
      description: "HTTP status code is {{ \$value }} (instance {{ \$labels.instance }})"

  - alert: HTTPSlowProbe
    # Blackbox Slow HTTP probe
    expr: avg_over_time(probe_duration_seconds[1m]) > 120
    for: 5m
    labels:
      severity: 'WARNING'
    annotations:
      title: 'Probe took more than 2 min to complete'
      runbook_url: https://ubona.atlassian.net/l/cp/450a4xNW
      dashboard_url: https://monitoring.ubona.com/goto/fU2NsyoSR?orgId=2
      description: "Endpoint HTTP Probe took {{ \$value }} (instance {{ \$labels.instance }})"
EOF

sudo chown -R prometheus:prometheus /etc/prometheus/rules/*

# Start and enable services
echo "Staring all the services in sequence.."
sudo systemctl daemon-reload
sudo systemctl enable blackbox
sudo systemctl start blackbox
sudo systemctl status blackbox --no-pager

#######################

#Remove Service
# sudo systemctl stop grafana.service
# sudo systemctl disable grafana.service
# sudo rm -rf /usr/share/grafana
