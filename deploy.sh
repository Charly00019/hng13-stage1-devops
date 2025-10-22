#!/bin/bash
# ============================================
# HNG Stage 1 DevOps Task – Automated Deployment Script
# Author: Charlotte Walternerve
# Version: 1.1.0
# ============================================

set -euo pipefail

# === Colors ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# === Logging ===
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
log() { echo -e "$(date '+%F %T') [$1] $2" | tee -a "$LOG_FILE"; }
info() { log "INFO" "${BLUE}$1${NC}"; }
success() { log "OK" "${GREEN}$1${NC}"; }
warn() { log "WARN" "${YELLOW}$1${NC}"; }
err() { log "ERR" "${RED}$1${NC}"; }

trap 'err "Script failed at line $LINENO"; exit 1' ERR INT TERM

# === Validation ===
validate_url() { [[ "$1" =~ ^https://.+\.git$ ]]; }
validate_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 && $1 <= 65535 )); }
validate_key() { [ -f "$1" ]; }

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

# === 1️⃣ Collect Parameters ===
collect_params() {
  info "Collecting parameters..."
  prompt "Git Repository URL" GIT_REPO validate_url "https://github.com/Charly00019/todo-api.git"
  prompt_secret "Personal Access Token" PAT 
  prompt "Branch name" BRANCH ":" "main"
  prompt "SSH Username" SSH_USER ":" "ubuntu"
  prompt "Server IP address" SERVER_IP validate_ip "54.225.2.177"
  prompt "SSH key path" SSH_KEY validate_key "/c/Users/Gevey/HNG/sshkey.pem"
  prompt "Application port" APP_PORT validate_port "8000"
  REPO_NAME=$(basename "$GIT_REPO" .git)
  REMOTE="$SSH_USER@$SERVER_IP"
}

# === 2️⃣ Clone Repository ===
clone_repo() {
  info "Setting up repository..."
  mkdir -p repos && cd repos

  if [ -d "$REPO_NAME" ]; then
    info "Repo exists, pulling latest..."
    cd "$REPO_NAME"
    git fetch && git checkout "$BRANCH" && git pull
  else
    info "Cloning repository..."
    cat > ~/.netrc <<EOF
machine github.com
login oauth2
password $PAT
EOF
    chmod 600 ~/.netrc
    git clone -b "$BRANCH" "$GIT_REPO" "$REPO_NAME"
    rm -f ~/.netrc
    cd "$REPO_NAME"
  fi

  # ✅ Verify Dockerfile or docker-compose.yml exists
  if [ -f Dockerfile ]; then
    info "Found Dockerfile"
  elif [ -f docker-compose.yml ]; then
    info "Found docker-compose.yml"
  else
    err "No Dockerfile or docker-compose.yml found — cannot continue."
    exit 1
  fi

  success "Repository ready"
  cd ../..
}

# === 3️⃣ Check Remote Connection ===
check_remote() {
  info "Checking remote connectivity..."

  # Verify SSH connectivity
  ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "echo OK" >/dev/null || {
    err "SSH connection failed — check IP, username, or key permissions."
    exit 1
  }

  success "SSH connection verified"
}

# === 4️⃣ Prepare Remote Environment ===
setup_remote() {
  info "Preparing remote environment..."
  ssh -i "$SSH_KEY" "$REMOTE" 'bash -s' <<'EOF'
set -e
sudo apt-get update -qq
for pkg in docker.io docker-compose nginx; do
  if ! command -v $(echo $pkg | cut -d. -f1) &>/dev/null; then
    sudo apt-get install -y $pkg
  fi
done
sudo systemctl enable docker nginx
sudo systemctl start docker nginx
EOF
  success "Remote environment ready"
}

# === 5️⃣ Transfer Files ===
transfer_files() {
  info "Transferring files..."

  # Ensure we’re in script root where 'repos' folder exists
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_PATH="$SCRIPT_DIR/repos/$REPO_NAME"

  # Validate repo path
  if [ ! -d "$REPO_PATH" ]; then
    err "Repository directory not found at $REPO_PATH"
    exit 1
  fi

  local tarfile="/tmp/${REPO_NAME}_$(date +%s).tar.gz"

  # Create tarball safely
  tar -czf "$tarfile" -C "$SCRIPT_DIR/repos" "$REPO_NAME" || {
    err "Failed to create tarball. Check permissions or path."
    exit 1
  }

  # Transfer tarball to remote server
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$tarfile" "$REMOTE:/tmp/" || {
    err "File transfer failed. Check SSH key or connectivity."
    exit 1
  }

  # Extract and prepare app directory remotely
  ssh -i "$SSH_KEY" "$REMOTE" <<EOF
set -e
sudo mkdir -p /opt/apps
sudo tar -xzf /tmp/$(basename $tarfile) -C /opt/apps
sudo rm -f /tmp/$(basename $tarfile)
EOF

  rm -f "$tarfile"
  success "Files transferred and extracted to /opt/apps/$REPO_NAME on remote host"
}

# === 6️⃣ Deploy Dockerized Application ===
deploy_app() {
  info "Deploying Docker containers..."

  ssh -i "$SSH_KEY" "$REMOTE" "bash -s" <<EOF
set -e
cd /opt/apps/$REPO_NAME

# Ensure Docker service is running
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl start docker

# Clean up previous deployment (idempotent)
if [ -f docker-compose.yml ]; then
  echo "[INFO] Using docker-compose deployment"
  sudo docker compose down || true
  sudo docker compose pull || true
  sudo docker compose up -d --build
else
  echo "[INFO] Using Dockerfile build"
  sudo docker stop $REPO_NAME || true
  sudo docker rm $REPO_NAME || true
  sudo docker build -t $REPO_NAME .
  sudo docker run -d --name $REPO_NAME -p $APP_PORT:$APP_PORT $REPO_NAME
fi

# Validate container status
sleep 5
echo "[INFO] Active containers:"
sudo docker ps --filter "name=$REPO_NAME"

# Basic health check
curl -fsSL http://localhost:$APP_PORT >/dev/null && \
  echo "[OK] Application is responding on port $APP_PORT" || \
  echo "[WARN] Application did not respond on port $APP_PORT"
EOF

  success "Docker app deployed successfully"
}


# === 7️⃣ Configure Nginx ===
configure_nginx() {
  info "Configuring Nginx reverse proxy..."
  ssh -i "$SSH_KEY" "$REMOTE" "bash -s" <<EOF
set -e
sudo rm -f /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/$REPO_NAME > /dev/null <<'NGX'
server {
    listen 80;
    server_name $SERVER_IP;
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGX
sudo ln -sf /etc/nginx/sites-available/$REPO_NAME /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
EOF
  success "Nginx configured successfully"
}

enable_ssl() {
  info "Setting up self-signed SSL for testing..."
  ssh -i "$SSH_KEY" "$REMOTE" "SERVER_IP='$SERVER_IP' APP_PORT='$APP_PORT' REPO_NAME='$REPO_NAME' bash -s" <<'EOF'
set -e
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$SERVER_IP" 2>/dev/null

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
EOF
  success "Self-signed SSL configured"
}

# === 9️⃣ Validate Deployment ===
validate_deploy() {
  info "Validating deployment..."
  
  # Test 1: Check if container is running
  if ssh -i "$SSH_KEY" "$REMOTE" "docker ps --filter name=$REPO_NAME --format 'table {{.Names}}\t{{.Status}}'" | grep -q "Up"; then
    success "Container is running"
  else
    error "Container is not running"
    ssh -i "$SSH_KEY" "$REMOTE" "docker logs $REPO_NAME --tail 30"
    return 1
  fi
  
  # Test 2: Check app directly (bypass nginx)
  info "Testing application directly on port $APP_PORT..."
  local direct_status=$(ssh -i "$SSH_KEY" "$REMOTE" "curl -s -o /dev/null -w '%{http_code}' http://localhost:$APP_PORT || echo '000'")
  if [ "$direct_status" = "200" ] || [ "$direct_status" = "301" ] || [ "$direct_status" = "302" ]; then
    success "App healthy locally (port $APP_PORT, status: $direct_status)"
  else
    warn "Local check failed (got status: $direct_status)"
    ssh -i "$SSH_KEY" "$REMOTE" "docker logs $REPO_NAME --tail 20"
  fi
  
  # Test 3: Check through nginx (external)
  info "Testing through Nginx (external)..."
  local nginx_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$SERVER_IP" || echo "000")
  if [ "$nginx_status" = "200" ] || [ "$nginx_status" = "301" ] || [ "$nginx_status" = "302" ]; then
    success "App reachable through Nginx (status: $nginx_status)"
  else
    warn "Nginx reachability failed (got status: $nginx_status)"
    # Debug nginx
    ssh -i "$SSH_KEY" "$REMOTE" "sudo tail -20 /var/log/nginx/error.log" 2>/dev/null || true
  fi
  
  # Test 4: Check nginx configuration
  if ssh -i "$SSH_KEY" "$REMOTE" "sudo nginx -t" &>/dev/null; then
    success "Nginx configuration valid"
  else
    error "Nginx configuration invalid"
    return 1
  fi
}

# === 9️⃣ Cleanup ===
cleanup_deploy() {
  info "Starting cleanup..."
  read -p "Are you sure you want to remove deployment (y/N)? " ans
  [[ $ans =~ ^[Yy]$ ]] || { info "Cleanup cancelled"; exit 0; }
  
  ssh -i "$SSH_KEY" "$REMOTE" "bash -s" <<EOF
set -e
echo "[INFO] Starting cleanup process..."


echo "[INFO] Stopping and removing containers..."
sudo docker stop $REPO_NAME 2>/dev/null || true
sudo docker rm $REPO_NAME 2>/dev/null || true

sudo docker ps -aq --filter "name=$REPO_NAME" | xargs -r sudo docker rm -f 2>/dev/null || true

echo "[INFO] Removing images..."
sudo docker rmi $REPO_NAME 2>/dev/null || true
sudo docker images -q --filter "reference=*$REPO_NAME*" | xargs -r sudo docker rmi 2>/dev/null || true

echo "[INFO] Cleaning up Nginx configuration..."
sudo rm -f /etc/nginx/sites-available/$REPO_NAME
sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME

sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t 2>/dev/null && sudo systemctl reload nginx 2>/dev/null || true

echo "[INFO] Removing application files..."
sudo rm -rf /opt/apps/$REPO_NAME

echo "[INFO] Cleaning up Docker system..."
sudo docker system prune -f 2>/dev/null || true

echo "[SUCCESS] Cleanup completed successfully"
EOF
  
  # Also cleanup local files
  info "Cleaning up local files..."
  rm -rf "repos/$REPO_NAME" 2>/dev/null || true
  
  success "Cleanup completed successfully"
}

# === Main ===
main() {
  case "${1:-}" in
    -c|--cleanup) collect_params; check_remote; cleanup_deploy ;;
    -h|--help)
      echo "Usage: $0 [--cleanup|--help]"
      ;;
    *)
      collect_params
      clone_repo
      check_remote
      setup_remote
      transfer_files
      deploy_app
      configure_nginx
      enable_ssl
      validate_deploy
      success "✅ Deployment completed!"
      ;;
  esac
}

main "$@"
