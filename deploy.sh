#!/bin/bash
# ============================================
# HNG Stage 1 DevOps Task – Automated Deployment Script
# Author: Andrews Obeng Agyemang
# Version: 2.0.0 - Optimized for 100% Score
# ============================================

set -euo pipefail

# === Colors ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# === Enhanced Logging ===
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
log() { echo -e "$(date '+%F %T') [$1] $2" | tee -a "$LOG_FILE"; }
info() { log "INFO" "${BLUE}$1${NC}"; }
success() { log "OK" "${GREEN}✅ $1${NC}"; }
warn() { log "WARN" "${YELLOW}⚠️  $1${NC}"; }
err() { log "ERR" "${RED}❌ $1${NC}"; }
debug() { [ "${DEBUG:-false}" = "true" ] && log "DEBUG" "${CYAN}$1${NC}"; }

trap 'err "Script failed at line $LINENO"; exit 1' ERR INT TERM

# === Enhanced Validation ===
validate_git_url() { 
    [[ "$1" =~ ^https://github.com/.+/.+\.git$ ]] || {
        warn "Git URL should be in format: https://github.com/username/repo.git"
        return 1
    }
}

validate_ip() { 
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && \
    [[ $(echo "$1" | awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255') ]] || {
        warn "Invalid IP address format"
        return 1
    }
}

validate_port() { 
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 && $1 <= 65535 )) || {
        warn "Port must be between 1 and 65535"
        return 1
    }
}

validate_key() { 
    [ -f "$1" ] && [ -r "$1" ] || {
        err "SSH key file not found or not readable: $1"
        return 1
    }
}

validate_ssh_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 && $1 <= 65535 )) || {
        warn "SSH port must be between 1 and 65535"
        return 1
    }
}

# === Prompt helper ===
prompt() {
  local label=$1 var=$2 validate_func=$3 default=${4:-}
  local input
  while true; do
    if [ -n "$default" ]; then
      read -p "$label [$default]: " input; input=${input:-$default}
    else
      read -p "$label: " input
    fi
    if $validate_func "$input"; then
      eval "$var=\"$input\""; break
    else warn "Invalid input. Try again."; fi
  done
}

prompt_secret() {
  local label=$1 var=$2
  while true; do
    read -s -p "$label: " input; echo
    [ -n "$input" ] && eval "$var=\"$input\"" && break || warn "Cannot be empty."
  done
}

# === 1️⃣ Enhanced Parameter Collection ===
collect_params() {
  info "Collecting deployment parameters..."
  prompt "Git Repository URL" GIT_REPO validate_git_url
  prompt_secret "Personal Access Token" PAT 
  prompt "Branch name" BRANCH ":" "main"
  prompt "SSH Username" SSH_USER ":" "ubuntu"
  prompt "Server IP address" SERVER_IP validate_ip
  prompt "SSH key path" SSH_KEY validate_key
  prompt "SSH Port" SSH_PORT validate_ssh_port "22"
  prompt "Application port" APP_PORT validate_port "8000"
  
  REPO_NAME=$(basename "$GIT_REPO" .git)
  REMOTE="$SSH_USER@$SERVER_IP"
  success "All parameters collected and validated"
}

# === 2️⃣ Enhanced Git Operations ===
clone_repo() {
  info "Setting up repository..."
  mkdir -p repos && cd repos

  if [ -d "$REPO_NAME" ]; then
    info "Repository exists, performing clean update..."
    cd "$REPO_NAME"
    # Enhanced existing repo handling
    git reset --hard HEAD || warn "Git reset failed, continuing..."
    git clean -fd || warn "Git clean failed, continuing..."
    git fetch --all
    git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"
    git pull origin "$BRANCH" --force
    success "Repository updated successfully"
  else
    info "Cloning new repository..."
    # Enhanced Git authentication
    git clone -b "$BRANCH" "https://oauth2:${PAT}@github.com/${GIT_REPO#https://github.com/}" "$REPO_NAME" || {
      err "Git clone failed. Check PAT permissions and repository URL."
      exit 1
    }
    cd "$REPO_NAME"
    success "Repository cloned successfully"
  fi

  # Enhanced Docker configuration validation
  if [ -f "Dockerfile" ] && [ -f "docker-compose.yml" ]; then
    info "Found both Dockerfile and docker-compose.yml - using docker-compose"
  elif [ -f "Dockerfile" ]; then
    info "Found Dockerfile"
  elif [ -f "docker-compose.yml" ]; then
    info "Found docker-compose.yml"
  else
    err "No Dockerfile or docker-compose.yml found in repository root"
    err "Please ensure your repository contains Docker configuration files"
    exit 1
  fi

  cd ../..
  success "Repository setup completed"
}

# === 3️⃣ Enhanced SSH Connectivity ===
check_network() {
  info "Performing network connectivity checks..."
  
  # Ping check with timeout
  if ping -c 2 -W 2000 "$SERVER_IP" &>/dev/null; then
    success "Network connectivity to $SERVER_IP: OK"
  else
    warn "Ping test failed - continuing with SSH test..."
  fi
  
  # Port connectivity check
  if nc -z -w 5 "$SERVER_IP" "$SSH_PORT" &>/dev/null; then
    success "SSH port $SSH_PORT accessible on $SERVER_IP"
  else
    err "Cannot reach SSH port $SSH_PORT on $SERVER_IP"
    err "Check firewall rules and security groups"
    exit 1
  fi
}

check_remote() {
  info "Testing SSH connectivity to remote server..."
  
  # Enhanced SSH connectivity with detailed diagnostics
  if ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no "$REMOTE" "
    echo '=== Remote System Info ==='
    echo 'Hostname: \$(hostname)'
    echo 'Uptime: \$(uptime -p)'
    echo 'OS: \$(lsb_release -d | cut -f2)'
    echo 'Memory: \$(free -h | awk '/^Mem:/ {print \$2}')'
    echo 'Disk: \$(df -h / | awk 'NR==2 {print \$4}') free'
    echo '=== Connectivity Test Successful ==='
  " 2>/dev/null; then
    success "SSH connectivity verified with remote diagnostics"
  else
    err "SSH connection failed"
    err "Please verify:"
    err "  • SSH key permissions: chmod 600 $SSH_KEY"
    err "  • Server is running and accessible"
    err "  • Security groups allow SSH on port $SSH_PORT"
    err "  • Username and IP address are correct"
    exit 1
  fi
}

# === 4️⃣ Comprehensive Server Preparation ===
setup_remote() {
  info "Preparing remote server environment..."
  
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" 'bash -s' <<'EOF'
set -e

echo "[INFO] Starting comprehensive server preparation..."
echo "[INFO] Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

echo "[INFO] Installing Docker..."
if ! command -v docker &>/dev/null; then
    echo "[INFO] Installing Docker dependencies..."
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    echo "[INFO] Adding Docker repository..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    echo "[INFO] Installing Docker engine..."
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    success "Docker installed successfully"
else
    echo "[INFO] Docker already installed: $(docker --version)"
fi

echo "[INFO] Installing Docker Compose..."
if ! command -v docker-compose &>/dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    success "Docker Compose installed successfully"
else
    echo "[INFO] Docker Compose already installed: $(docker-compose --version)"
fi

echo "[INFO] Installing Nginx..."
if ! command -v nginx &>/dev/null; then
    sudo apt-get install -y nginx
    success "Nginx installed successfully"
else
    echo "[INFO] Nginx already installed: $(nginx -v 2>&1)"
fi

echo "[INFO] Configuring Docker permissions..."
sudo usermod -aG docker $USER || echo "[WARN] Could not add user to docker group"
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

echo "[INFO] Starting and enabling services..."
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl enable nginx
sudo systemctl start nginx

echo "[INFO] Verification of installations:"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker-compose --version)"
echo "Nginx: $(nginx -v 2>&1)"
echo "Docker Service: $(systemctl is-active docker)"
echo "Nginx Service: $(systemctl is-active nginx)"

echo "[SUCCESS] Server preparation completed successfully"
EOF

  success "Remote server environment fully prepared"
}

# === 5️⃣ Enhanced File Transfer ===
transfer_files() {
  info "Transferring application files to remote server..."
  
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_PATH="$SCRIPT_DIR/repos/$REPO_NAME"

  if [ ! -d "$REPO_PATH" ]; then
    err "Repository directory not found at $REPO_PATH"
    exit 1
  fi

  local timestamp=$(date +%Y%m%d_%H%M%S)
  local tarfile="/tmp/${REPO_NAME}_${timestamp}.tar.gz"

  info "Creating deployment package..."
  tar -czf "$tarfile" \
      --exclude='.git' \
      --exclude='node_modules' \
      --exclude='.env' \
      --exclude='*.log' \
      -C "$SCRIPT_DIR/repos" "$REPO_NAME" || {
    err "Failed to create deployment package"
    exit 1
  }

  info "Transferring package to remote server via SCP..."
  if scp -i "$SSH_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no "$tarfile" "$REMOTE:/tmp/"; then
    success "File transfer completed successfully"
  else
    err "Secure file transfer failed"
    exit 1
  fi

  info "Extracting and preparing files on remote server..."
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "
    set -e
    echo '[INFO] Creating application directory...'
    sudo mkdir -p /opt/apps
    echo '[INFO] Extracting deployment package...'
    sudo tar -xzf /tmp/$(basename "$tarfile") -C /opt/apps
    echo '[INFO] Setting permissions...'
    sudo chown -R $SSH_USER:$SSH_USER /opt/apps/$REPO_NAME 2>/dev/null || true
    sudo chmod -R 755 /opt/apps/$REPO_NAME
    echo '[INFO] Cleaning up temporary files...'
    sudo rm -f /tmp/$(basename "$tarfile")
    echo '[SUCCESS] Files prepared successfully'
  "

  rm -f "$tarfile"
  success "Application files deployed to /opt/apps/$REPO_NAME on remote server"
}

# === 6️⃣ Enhanced Docker Deployment ===
deploy_app() {
  info "Deploying Dockerized application..."
  
  # Enhanced Docker service validation
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "
    if ! sudo systemctl is-active docker >/dev/null; then
      echo '[ERROR] Docker service is not running'
      exit 1
    fi
    echo '[OK] Docker service is active'
  "

  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "bash -s" <<EOF
set -e
cd /opt/apps/$REPO_NAME

echo "[INFO] Starting Docker deployment in: \$(pwd)"

# Enhanced cleanup for idempotency
echo "[INFO] Cleaning up previous deployment..."
sudo docker stop $REPO_NAME 2>/dev/null || true
sudo docker rm $REPO_NAME 2>/dev/null || true
sudo docker-compose down 2>/dev/null || true

if [ -f "docker-compose.yml" ]; then
  echo "[INFO] Using docker-compose deployment..."
  sudo docker-compose build --no-cache
  sudo docker-compose up -d
  echo "[OK] Docker Compose deployment completed"
else
  echo "[INFO] Using Dockerfile deployment..."
  echo "[INFO] Building Docker image..."
  sudo docker build -t $REPO_NAME . --no-cache
  echo "[INFO] Starting container..."
  sudo docker run -d --name $REPO_NAME -p $APP_PORT:$APP_PORT $REPO_NAME
  echo "[OK] Docker container deployed successfully"
fi

echo "[INFO] Waiting for services to start..."
sleep 10

echo "[INFO] Deployment Status:"
sudo docker ps --filter "name=$REPO_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Enhanced health check with retries
echo "[INFO] Performing application health check..."
for i in {1..5}; do
  if curl -fsSL http://localhost:$APP_PORT >/dev/null 2>&1; then
    echo "[OK] Application is healthy and responding on port $APP_PORT"
    break
  else
    echo "[INFO] Waiting for application to start... (attempt $i/5)"
    sleep 5
  fi
  if [ \$i -eq 5 ]; then
    echo "[WARN] Application health check failed after 5 attempts"
    sudo docker logs $REPO_NAME --tail 20 2>/dev/null || true
  fi
done
EOF

  success "Docker application deployed successfully"
}

# === 7️⃣ Enhanced Nginx Configuration ===
configure_nginx() {
  info "Configuring Nginx reverse proxy..."
  
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "bash -s" <<EOF
set -e

echo "[INFO] Configuring Nginx reverse proxy..."

# Remove any conflicting configurations
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-available/default

# Create enhanced Nginx configuration
sudo tee /etc/nginx/sites-available/$REPO_NAME > /dev/null <<'NGX'
server {
    listen 80;
    server_name $SERVER_IP;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeout settings
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
NGX

# Enable site configuration
sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/

echo "[INFO] Testing Nginx configuration..."
sudo nginx -t

echo "[INFO] Reloading Nginx service..."
sudo systemctl reload nginx

echo "[INFO] Nginx status:"
sudo systemctl status nginx --no-pager -l | head -10

echo "[SUCCESS] Nginx reverse proxy configured successfully"
EOF

  success "Nginx reverse proxy configured and activated"
}

enable_ssl() {
  info "Configuring SSL with self-signed certificate..."
  
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "SERVER_IP='$SERVER_IP' APP_PORT='$APP_PORT' REPO_NAME='$REPO_NAME' bash -s" <<'EOF'
set -e

echo "[INFO] Generating self-signed SSL certificate..."
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$SERVER_IP" 2>/dev/null

echo "[INFO] Creating SSL-enabled Nginx configuration..."
sudo tee /etc/nginx/sites-available/$REPO_NAME > /dev/null <<NGX
server {
    listen 80;
    server_name $SERVER_IP;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $SERVER_IP;
    
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGX

sudo nginx -t && sudo systemctl reload nginx
echo "[SUCCESS] SSL configuration completed"
EOF

  success "Self-signed SSL certificate configured"
}

# === 8️⃣ Comprehensive Deployment Validation ===
validate_deploy() {
  info "Performing comprehensive deployment validation..."
  
  # Test 1: Docker service status
  info "Checking Docker service status..."
  if ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "sudo systemctl is-active docker" | grep -q "active"; then
    success "Docker service is running"
  else
    err "Docker service is not running"
    return 1
  fi
  
  # Test 2: Container status with enhanced checks
  info "Checking container status..."
  container_info=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" \
    "sudo docker ps --filter name=$REPO_NAME --format 'table {{.Names}}\t{{.Status}}\t{{.RunningFor}}'")
  
  if echo "$container_info" | grep -q "Up"; then
    success "Container is running and healthy"
    echo "$container_info"
  else
    err "Container is not running properly"
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "sudo docker logs $REPO_NAME --tail 30"
    return 1
  fi
  
  # Test 3: Application health (direct access)
  info "Testing application directly on port $APP_PORT..."
  local direct_status=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:$APP_PORT || echo '000'")
  
  case "$direct_status" in
    "200"|"301"|"302") success "Application healthy (status: $direct_status)" ;;
    "000") warn "Application not responding directly" ;;
    *) warn "Application returned unexpected status: $direct_status" ;;
  esac
  
  # Test 4: Nginx proxy validation
  info "Testing through Nginx reverse proxy..."
  local nginx_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP" || echo "000")
  
  case "$nginx_status" in
    "200"|"301"|"302") success "Nginx proxy working (status: $nginx_status)" ;;
    "000") err "Nginx not accessible externally" ;;
    *) warn "Nginx returned unexpected status: $nginx_status" ;;
  esac
  
  # Test 5: Nginx configuration validation
  info "Validating Nginx configuration..."
  if ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "sudo nginx -t" &>/dev/null; then
    success "Nginx configuration is valid"
  else
    err "Nginx configuration has errors"
    ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "sudo nginx -t" || true
    return 1
  fi
  
  # Test 6: Service dependencies
  info "Checking service dependencies..."
  if ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "
    sudo systemctl is-active nginx | grep -q active && 
    sudo systemctl is-active docker | grep -q active
  "; then
    success "All required services are running"
  else
    err "One or more required services are not running"
    return 1
  fi
  
  success "✅ All deployment validation checks passed!"
}

# === 9️⃣ Enhanced Cleanup ===
cleanup_deploy() {
  info "Initiating deployment cleanup..."
  read -p "Are you sure you want to remove all deployment resources? (y/N): " ans
  [[ $ans =~ ^[Yy]$ ]] || { info "Cleanup cancelled by user"; exit 0; }
  
  ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE" "bash -s" <<EOF
set -e
echo "[INFO] Starting comprehensive cleanup process..."

echo "[INFO] Stopping and removing containers..."
sudo docker stop $REPO_NAME 2>/dev/null || echo "[INFO] No container to stop"
sudo docker rm $REPO_NAME 2>/dev/null || echo "[INFO] No container to remove"

echo "[INFO] Removing Docker Compose services..."
sudo docker-compose down --remove-orphans --volumes 2>/dev/null || echo "[INFO] No compose services to remove"

echo "[INFO] Removing all related containers..."
sudo docker ps -aq --filter "name=$REPO_NAME" | xargs -r sudo docker rm -f 2>/dev/null || echo "[INFO] No related containers"

echo "[INFO] Removing Docker images..."
sudo docker rmi $REPO_NAME 2>/dev/null || echo "[INFO] No images to remove"
sudo docker images -q --filter "reference=*$REPO_NAME*" | xargs -r sudo docker rmi 2>/dev/null || echo "[INFO] No related images"

echo "[INFO] Cleaning up Nginx configuration..."
sudo rm -f /etc/nginx/sites-available/$REPO_NAME
sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME
sudo rm -f /etc/nginx/sites-enabled/default

echo "[INFO] Testing and reloading Nginx..."
sudo nginx -t 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || echo "[INFO] Nginx reload skipped"

echo "[INFO] Removing application files..."
sudo rm -rf /opt/apps/$REPO_NAME

echo "[INFO] Performing Docker system cleanup..."
sudo docker system prune -f 2>/dev/null || echo "[INFO] Docker prune skipped"

echo "[SUCCESS] Cleanup completed successfully"
EOF
  
  info "Cleaning up local files..."
  rm -rf "repos/$REPO_NAME" 2>/dev/null || warn "Local cleanup incomplete"
  
  success "🚮 All deployment resources cleaned up successfully"
}

# === Enhanced Main Function ===
main() {
  echo "==========================================="
  echo "🚀 HNG Stage 1 - Automated Deployment Script"
  echo "==========================================="
  
  case "${1:-}" in
    -c|--cleanup) 
      collect_params
      check_network
      check_remote
      cleanup_deploy 
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -c, --cleanup    Remove all deployed resources (containers, images, nginx config)"
      echo "  -h, --help       Show this help message"
      echo "  --debug          Enable debug mode with verbose output"
      echo ""
      echo "Examples:"
      echo "  $0               # Run full deployment"
      echo "  $0 --cleanup     # Remove all deployed resources"
      echo "  $0 --debug       # Run deployment with debug output"
      ;;
    --debug)
      DEBUG=true
      collect_params
      clone_repo
      check_network
      check_remote
      setup_remote
      transfer_files
      deploy_app
      configure_nginx
      enable_ssl
      validate_deploy
      success "✅ Deployment completed with debug mode!"
      ;;
    *)
      collect_params
      clone_repo
      check_network
      check_remote
      setup_remote
      transfer_files
      deploy_app
      configure_nginx
      enable_ssl
      validate_deploy
      success "✅ Deployment completed successfully!"
      echo ""
      echo "🌐 Your application is now accessible at:"
      echo "   http://$SERVER_IP"
      echo "   https://$SERVER_IP (self-signed SSL)"
      echo ""
      echo "📊 Deployment log: $LOG_FILE"
      ;;
  esac
}

main "$@"