#!/bin/bash

# Hadoop Ecosystem Utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Initialize logging
init_logging() {
    echo "================================================================" > "$LOG_FILE"
    echo "Hadoop Ecosystem Setup Log for $(hostname)" >> "$LOG_FILE"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "Role: ${NODE_ROLE:-unknown}" >> "$LOG_FILE"
    echo "================================================================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Check state
check_state() {
    local step="$1"
    [[ -f "${STATE_DIR}/${step}_completed" ]]
}

# Mark step complete
mark_complete() {
    local step="$1"
    mkdir -p "$STATE_DIR"
    touch "${STATE_DIR}/${step}_completed"
    log_success "Step $step marked as completed"
}

# Retry command with exponential backoff
retry_command() {
    local cmd="$1"
    local max_attempts="$2"
    local attempt=1
    local delay=1

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Command failed after $max_attempts attempts: $cmd"
            return 1
        fi
        
        log_warning "Command failed, retrying in ${delay}s..."
        sleep $delay
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

# Wait for service to be active
wait_for_service() {
    local service="$1"
    local timeout="${2:-30}"
    local interval="${3:-5}"
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if sudo systemctl is-active "$service" >/dev/null 2>&1; then
            log_success "$service is active"
            return 0
        fi
        log_info "Waiting for $service to be active... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "$service failed to become active within $timeout seconds"
    return 1
}

# Validate environment
validate_environment() {
    log_info "Validating environment..."
    
    # Check if running as ubuntu user
    if [[ "$(whoami)" != "ubuntu" ]]; then
        log_error "Must run as ubuntu user"
        return 1
    fi
    
    # Check if sudo works
    if ! sudo -n true 2>/dev/null; then
        log_error "Sudo access required"
        return 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        log_warning "No internet connectivity detected"
    fi
    
    log_success "Environment validation passed"
    return 0
}

# Download and extract archive
download_and_extract() {
    local url="$1"
    local dest_dir="$2"
    local archive_name=$(basename "$url")
    local temp_dir="/tmp/hadoop-downloads"
    
    mkdir -p "$temp_dir"
    
    log_info "Downloading $archive_name..."
    if ! curl -L -o "$temp_dir/$archive_name" "$url"; then
        log_error "Failed to download $archive_name"
        return 1
    fi
    
    log_info "Extracting $archive_name to $dest_dir..."
    sudo mkdir -p "$dest_dir"
    
    if [[ "$archive_name" == *.tar.gz ]] || [[ "$archive_name" == *.tgz ]]; then
        sudo tar -xzf "$temp_dir/$archive_name" -C "$dest_dir" --strip-components=1
    elif [[ "$archive_name" == *.tar ]]; then
        sudo tar -xf "$temp_dir/$archive_name" -C "$dest_dir" --strip-components=1
    elif [[ "$archive_name" == *.zip ]]; then
        sudo unzip -q "$temp_dir/$archive_name" -d "$temp_dir/extract"
        sudo cp -r "$temp_dir/extract"/*/* "$dest_dir/"
    else
        log_error "Unsupported archive format: $archive_name"
        return 1
    fi
    
    sudo chown -R ubuntu:ubuntu "$dest_dir"
    rm -f "$temp_dir/$archive_name"
    
    log_success "$archive_name extracted successfully"
}

# Create systemd service
create_systemd_service() {
    local service_name="$1"
    local exec_start="$2"
    local user="${3:-ubuntu}"
    local description="${4:-$service_name service}"
    local environment_vars="${5:-}"
    
    log_info "Creating systemd service: $service_name"
    
    sudo tee "/etc/systemd/system/${service_name}.service" > /dev/null <<EOF
[Unit]
Description=$description
After=network.target

[Service]
Type=forking
User=$user
Group=$user
ExecStart=$exec_start
Restart=always
RestartSec=10
$environment_vars

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    
    log_success "Systemd service $service_name created"
}

# Set environment variables
set_environment() {
    local var_name="$1"
    local var_value="$2"
    local profile_file="/home/ubuntu/.bashrc"
    
    if ! grep -q "export ${var_name}=" "$profile_file"; then
        echo "export ${var_name}=${var_value}" >> "$profile_file"
        log_info "Added $var_name to environment"
    fi
    
    export "$var_name"="$var_value"
}

# Check if port is open
check_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Create user if not exists
create_user_if_not_exists() {
    local username="$1"
    local home_dir="$2"
    
    if ! id "$username" &>/dev/null; then
        log_info "Creating user: $username"
        sudo useradd -m -d "$home_dir" -s /bin/bash "$username"
        sudo usermod -aG sudo "$username"
        log_success "User $username created"
    else
        log_info "User $username already exists"
    fi
}

# Wait for port to be available
wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local interval="${4:-5}"
    local elapsed=0
    
    log_info "Waiting for port $host:$port to be available..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if check_port "$host" "$port"; then
            log_success "Port $host:$port is available"
            return 0
        fi
        log_info "Waiting for port $host:$port... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Port $host:$port not available after $timeout seconds"
    return 1
}
