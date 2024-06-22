#!/bin/bash

# Install Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

# Check and install lsof if not installed
if ! command -v lsof &> /dev/null; then
    echo "lsof not installed, installing..."
    sudo apt-get update
    sudo apt-get install -y lsof
fi

# Configuration file path
CONFIG_FILE="/etc/hysteria/config.yaml"

# Generate a random UUIDv4
PASSWORD=$(uuidgen)

# Get user input for port number and domain
read -p "Enter port number: " PORT
# Check if the port is in use
if lsof -i:"$PORT" >/dev/null; then
    echo "Port $PORT is already in use, please choose another port."
    exit 1
fi


read -p "Enter domain (default: bing.com): " DOMAIN
# Use default domain if none provided
if [ -z "$DOMAIN" ]; then
    DOMAIN="bing.com"
fi

# Create /etc/hysteria directory
sudo mkdir -p /etc/hysteria

# Create hysteria user if it doesn't exist
if ! id -u hysteria &> /dev/null; then
    echo "hysteria user does not exist, creating..."
    sudo useradd -r -s /bin/false hysteria
fi

# Generate certificate and key
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$DOMAIN" -days 36500
sudo chown hysteria /etc/hysteria/server.key
sudo chown hysteria /etc/hysteria/server.crt

# Get certificate fingerprint
FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -in /etc/hysteria/server.crt)

# Write new configuration content
cat << EOF | sudo tee $CONFIG_FILE
listen: :$PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://$DOMAIN
    rewriteHost: true
EOF

# Create systemd service file for Hysteria2
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
cat << EOF | sudo tee $SERVICE_FILE
[Unit]
Description=Hysteria Server Service (config.yaml)
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria -c /etc/hysteria/config.yaml server
Restart=on-failure
User=hysteria
Group=hysteria

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon and start Hysteria2 service
sudo systemctl daemon-reload
sudo systemctl start hysteria-server.service
sudo systemctl enable hysteria-server.service

# Check Hysteria2 service status
sudo systemctl status hysteria-server.service

# Output results
echo "Configuration file updated: $CONFIG_FILE"
echo "Generated UUIDv4 password: $PASSWORD"
echo "Certificate fingerprint: $FINGERPRINT"
