#!/bin/bash

# Kubernetes Setup Utility Functions
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Logging functions
log_info() {
    local timestamp=$(get_timestamp)
    local message="${BLUE}[INFO]${NC} ${timestamp} $1"
    echo -e "$message"
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_success() {
    local timestamp=$(get_timestamp)
    local message="${GREEN}[SUCCESS]${NC} ${timestamp} $1"
    echo -e "$message"
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_warning() {
    local timestamp=$(get_timestamp)
    local message="${YELLOW}[WARNING]${NC} ${timestamp} $1"
    echo -e "$message"
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_error() {
    local timestamp=$(get_timestamp)
    local message="${RED}[ERROR]${NC} ${timestamp} $1"
    echo -e "$message" >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Initialize logging
init_logging() {
    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE="/tmp/k8s-setup.log"
    fi

    local log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true

    {
        echo "================================================================"
        echo "Kubernetes Setup Log for $(hostname)"
        echo "Started: $(get_timestamp)"
        echo "Role: ${NODE_ROLE:-unknown}"
        echo "================================================================"
        echo ""
    } > "$LOG_FILE" 2>/dev/null || true
}

# Check if step is already completed
check_state() {
    local step="$1"
    [[ -f "${STATE_DIR:-/tmp/k8s-state}/${step}_completed" ]]
}

# Mark step as completed
mark_complete() {
    local step="$1"
    local state_dir="${STATE_DIR:-/tmp/k8s-state}"

    mkdir -p "$state_dir" 2>/dev/null || {
        log_error "Cannot create state directory: $state_dir"
        return 1
    }

    if touch "${state_dir}/${step}_completed" 2>/dev/null; then
        log_success "Step $step marked as completed"
    else
        log_error "Failed to mark step $step as completed"
        return 1
    fi
}

# Retry command with exponential backoff
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-3}"
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

# Wait for service to be ready
wait_for_service() {
    local service="$1"
    local max_wait="${2:-60}"
    local wait_time=0

    log_info "Waiting for service $service to be ready..."

    while [[ $wait_time -lt $max_wait ]]; do
        if systemctl is-active --quiet "$service"; then
            log_success "Service $service is ready"
            return 0
        fi
        sleep 5
        wait_time=$((wait_time + 5))
        log_info "Waiting for $service... ($wait_time/$max_wait seconds)"
    done

    log_error "Service $service failed to start within $max_wait seconds"
    return 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system info
get_system_info() {
    local info=""
    info+="Hostname: $(hostname)\n"
    info+="OS: $(lsb_release -d | cut -f2)\n"
    info+="Kernel: $(uname -r)\n"
    info+="Architecture: $(uname -m)\n"
    info+="Memory: $(free -h | awk '/^Mem:/ {print $2}')\n"
    info+="CPU: $(nproc) cores\n"
    info+="Disk: $(df -h / | awk 'NR==2 {print $4}') free\n"
    echo -e "$info"
}