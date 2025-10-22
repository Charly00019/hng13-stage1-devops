# 🚀 Automated Deployment Script - HNG Stage 1 DevOps Task
A robust, production-grade Bash script that automates the setup, deployment, and configuration of a Dockerized application on a remote Linux server.

# 📋 Task Overview
This script fulfills the HNG Stage 1 DevOps Intern Task requirements by providing a complete automated deployment solution with proper error handling, validation, and logging.

# ✨ Features
🔐 Secure Authentication: PAT-based Git cloning and SSH key authentication

🔄 Idempotent Operations: Safe re-runs without breaking existing setups

📦 Docker Support: Both Dockerfile and docker-compose.yml deployment

🌐 Nginx Reverse Proxy: Automatic configuration and SSL readiness

📊 Comprehensive Logging: Timestamped log files for all operations

✅ Validation & Health Checks: End-to-end deployment validation

🧹 Cleanup Functionality: Complete resource cleanup with --cleanup flag

# 🛠️ Prerequisites
Local Machine: Bash shell (Linux/macOS/WSL)

Remote Server: Ubuntu-based Linux server

Access: SSH key access to remote server

GitHub: Personal Access Token (PAT) with repo access

# 🚀 Quick Start
1. Make Script Executable
```bash
chmod +x deploy.sh
```
2. Run Deployment
```bash
./deploy.sh
```
3. Cleanup (Optional Feature)
```bash
./deploy.sh --cleanup
```
# 📝 Usage
Interactive Mode
The script will prompt for all required parameters:

*** Git Repository URL**

*** Personal Access Token (PAT)**

***Branch name (default: main)**

*** SSH Username:**

*** Server IP address:**

*** SSH Key path:**

*** Application port:**

Command-line Options
```bash
./deploy.sh                    # Run full deployment
./deploy.sh --cleanup          # Remove all deployed resources (Optional Feature)
./deploy.sh --help            # Show help message
```

# 🎯 Task Requirements Implementation
1️⃣ Collect Parameters from User Input
Implementation: Interactive prompts with validation for all required parameters

```bash
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
```
# Features:

✅ Git Repository URL validation

✅ Secure PAT input (hidden)

✅ Branch name with default

✅ SSH credentials validation

✅ IP address validation

✅ Port number validation

2️⃣ Clone the Repository
Implementation: PAT authentication with idempotent clone/pull operations

```bash
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
```
# Features:

✅ PAT authentication via .netrc
✅ Idempotent operations (clone or pull)
✅ Docker configuration validation
✅ Branch switching support
3️⃣ Navigate into Cloned Directory
Implementation: Automatic directory navigation and Docker configuration verification

```bash
# Integrated in clone_repo() function
cd "$REPO_NAME"

# ✅ Verify Dockerfile or docker-compose.yml exists
if [ -f Dockerfile ]; then
  info "Found Dockerfile"
elif [ -f docker-compose.yml ]; then
  info "Found docker-compose.yml"
else
  err "No Dockerfile or docker-compose.yml found — cannot continue."
  exit 1
fi
```
# Features:

✅ Automatic directory navigation
✅ Docker configuration verification
✅ Clear error messaging
4️⃣ SSH into Remote Server

# Implementation: SSH connectivity verification and remote command execution

```bash
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
```
# Features:

✅ SSH connectivity verification
✅ Timeout and error handling
✅ Batch mode for automation

# 5️⃣ Prepare Remote Environment
Implementation: Automated installation of Docker, Docker Compose, and Nginx

```bash
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
```
# Features:

✅ System package updates
✅ Docker installation
✅ Docker Compose installation
✅ Nginx installation
✅ Service enabling and starting

# 6️⃣ Deploy Dockerized Application
Implementation: File transfer, Docker build, and container orchestration

```bash
# === 5️⃣ Transfer Files ===
transfer_files() {
  info "Transferring files..."
  # ... file transfer implementation
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
```
# Features:

✅ Secure file transfer via SCP
✅ Idempotent deployment (cleanup previous)
✅ Both Dockerfile and docker-compose support
✅ Container health checks
✅ Port mapping configuration

# 7️⃣ Configure Nginx as Reverse Proxy
Implementation: Dynamic Nginx configuration with SSL readiness

```bash
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
  # SSL configuration implementation
  success "Self-signed SSL configured"
}
```
# Features:

✅ Dynamic Nginx configuration
✅ Reverse proxy setup
✅ SSL readiness with self-signed certificates
✅ Configuration validation
✅ Service reload

# 8️⃣ Validate Deployment
Implementation: Comprehensive health checks and validation

```bash
# === 8️⃣ Validate Deployment ===
validate_deploy() {
  info "Validating deployment..."
  
  # Test 1: Check if container is running
  if ssh -i "$SSH_KEY" "$REMOTE" "docker ps --filter name=$REPO_NAME --format 'table {{.Names}}\t{{.Status}}'" | grep -q "Up"; then
    success "Container is running"
  else
    err "Container is not running"
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
    err "Nginx configuration invalid"
    return 1
  fi
}
```
# Features:

✅ Container status verification
✅ Application health checks
✅ Nginx proxy validation
✅ External accessibility testing
✅ Comprehensive error logging

# 9️⃣ Implement Logging and Error Handling
Implementation: Comprehensive logging system with error trapping

```bash
# === Logging ===
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
log() { echo -e "$(date '+%F %T') [$1] $2" | tee -a "$LOG_FILE"; }
info() { log "INFO" "${BLUE}$1${NC}"; }
success() { log "OK" "${GREEN}$1${NC}"; }
warn() { log "WARN" "${YELLOW}$1${NC}"; }
err() { log "ERR" "${RED}$1${NC}"; }

trap 'err "Script failed at line $LINENO"; exit 1' ERR INT TERM
```
# Features:

✅ Timestamped log files
✅ Color-coded log levels
✅ Console and file logging
✅ Error trapping and handling
✅ Line number tracking

# 🔟 Ensure Idempotency and Cleanup (Optional)
Implementation: Safe re-runs and complete resource cleanup

```bash
# === 9️⃣ Cleanup (Optional Feature) ===
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
```
# Features:

✅ --cleanup flag implementation
✅ Complete resource removal
✅ Safety confirmation prompt
✅ Idempotent operations
✅ Local and remote cleanup

# 📁 Project Structure
```text
deploy.sh                 # Main deployment script
deploy_YYYYMMDD_HHMMSS.log # Automated log files
repos/                   # Local repository cache
```
# 🔒 Security Features
*** PAT authentication for Git operations**

*** SSH key-based remote access**

*** Secure secret input (hidden PAT entry)**

*** Proper file permissions**

*** Validation of all user inputs**

🐛 Troubleshooting
Common Issues
SSH Connection Failed

Verify SSH key permissions: chmod 600 your-key.pem

Check server IP and username

Ensure security groups allow SSH access

Git Clone Failed

Verify PAT has repository access

Check repository URL format

Ensure PAT has correct scopes

Docker Build Failed

Check Dockerfile exists in repository

Verify Docker installation on remote server

Check application dependencies

Nginx Configuration Failed

Verify port availability

Check Nginx installation

Review error logs: sudo tail -f /var/log/nginx/error.log

# Debug Mode
For detailed debugging, run:

```bash
bash -x ./deploy.sh
```

# 📄License 
This project is part of the HNG Internship Stage 1 DevOps Task.

# 👥 Author
Andrews Obeng Agyemang
HNG DevOps Intern
