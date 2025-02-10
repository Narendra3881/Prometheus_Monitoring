#!/bin/bash

user_input=$1

# Trim any leading/trailing spaces from input
UNIT_LIST=$(echo "$user_input" | sed 's/^[ \t]*//;s/[ \t]*$//')

# Check if the user input is empty
if [ -z "$UNIT_LIST" ]; then
    echo "Error: No units specified."
    echo "Usage: Please provide space-separated unit names."
    exit 1
fi

# Combine the unit names into a format for the systemd_exporter
UNIT_LIST=$(echo "$UNIT_LIST" | sed 's/ /|/g')

echo "Units to monitor: $UNIT_LIST"

# Download the exporter
wget https://github.com/prometheus-community/systemd_exporter/releases/download/v0.6.0/systemd_exporter-0.6.0.linux-amd64.tar.gz || { echo "Download failed"; exit 1; }

# Extract files
tar xvf systemd_exporter-0.6.0.linux-amd64.tar.gz || { echo "Extraction failed"; exit 1; }

# Move binary to system path
sudo mv systemd_exporter-0.6.0.linux-amd64/systemd_exporter /usr/local/bin/ || { echo "Failed to move binary"; exit 1; }

# Clean up the downloaded tar file and extracted directory
rm -rf systemd_exporter-0.6.0.linux-amd64.tar.gz systemd_exporter-0.6.0.linux-amd64

# Define the service file path
SERVICE_FILE="/etc/systemd/system/systemd_exporter.service"

# Create the systemd service file using the unit list passed as parameter
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Systemd Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/systemd_exporter --systemd.collector.unit-include=($UNIT_LIST).service
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd daemon to recognize the new service
sudo systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }

# Start the service
sudo systemctl start systemd_exporter || { echo "Failed to start systemd_exporter"; exit 1; }

# Enable the service to start on boot
sudo systemctl enable systemd_exporter || { echo "Failed to enable systemd_exporter"; exit 1; }

# Check metrics
response=$(curl -s -w "%{http_code}" http://localhost:9558/metrics -o /dev/null)

# Check if curl received the complete response (HTTP 200 OK)
if [ "$response" -eq 200 ]; then
    echo "Request successful, 100% data received."
else
    echo "Error: Failed to retrieve data or incomplete response. HTTP Status Code: $response"
    exit 1
fi

