
#!/bin/bash

# Utility functions for Kubernetes setup
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

# State management functions
check_state() {
    local state_name="$1"
    local state_file="$STATE_DIR/${state_name}_completed"
    
    if [[ -f "$state_file" ]]; then
        return 0  # State exists (true)
    else
        return 1  # State doesn't exist (false)
    fi
}

mark_complete() {
    local state_name="$1"
    local state_file="$STATE_DIR/${state_name}_completed"
    
    mkdir -p "$STATE_DIR"
    touch "$state_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $state_name completed" >> "$state_file"
}

# Retry command function
retry_command() {
    local command="$1"
    local max_retries="$2"
    local delay="${3:-10}"
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Executing: $command (attempt $((retry_count + 1))/$max_retries)"
        
        if eval "$command"; then
            log_success "Command succeeded: $command"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Command failed, retrying in ${delay}s... (attempt $retry_count/$max_retries)"
                sleep "$delay"
            else
                log_error "Command failed after $max_retries attempts: $command"
                return 1
            fi
        fi
    done
}

# Wait for service function
wait_for_service() {
    local service_name="$1"
    local max_attempts="${2:-30}"
    local delay="${3:-5}"
    local attempt=0
    
    log_info "Waiting for service $service_name to be active..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if sudo systemctl is-active --quiet "$service_name"; then
            log_success "Service $service_name is active"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "Waiting for $service_name... ($attempt/$max_attempts)"
        sleep "$delay"
    done
    
    log_error "Service $service_name failed to become active after $((max_attempts * delay)) seconds"
    return 1
}

# Network connectivity check
check_connectivity() {
    local host="$1"
    local port="${2:-22}"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/$host/$port"; then
        log_success "Network connectivity to $host:$port successful"
        return 0
    else
        log_error "Network connectivity to $host:$port failed"
        return 1
    fi
}

# Cleanup function
cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        
        # Save debug information
        if [[ -n "$LOG_FILE" ]]; then
            echo "=== DEBUG INFORMATION ===" >> "$LOG_FILE"
            echo "Exit code: $exit_code" >> "$LOG_FILE"
            echo "Timestamp: $(date)" >> "$LOG_FILE"
            echo "Working directory: $(pwd)" >> "$LOG_FILE"
            echo "User: $(whoami)" >> "$LOG_FILE"
            echo "System info:" >> "$LOG_FILE"
            uname -a >> "$LOG_FILE" 2>/dev/null || true
            echo "=== END DEBUG ===" >> "$LOG_FILE"
        fi
    fi
    
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup_on_exit EXIT

# Validation functions
validate_ip() {
    local ip="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ $ip =~ $regex ]]; then
        # Check each octet
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

validate_cidr() {
    local cidr="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$"
    
    if [[ $cidr =~ $regex ]]; then
        local ip_part="${cidr%/*}"
        local prefix_part="${cidr#*/}"
        
        if validate_ip "$ip_part" && [[ $prefix_part -le 32 ]]; then
            return 0
        fi
    fi
    return 1
}

# System info functions
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$NAME $VERSION"
    else
        echo "Unknown OS"
    fi
}

get_memory_info() {
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_total / 1024 / 1024))
    echo "${mem_gb}GB"
}

get_cpu_info() {
    local cpu_count=$(nproc)
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//')
    echo "$cpu_count cores - $cpu_model"
}

# Environment validation
validate_environment() {
    log_info "=== Environment Validation ==="
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        return 1
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        log_error "Sudo access required"
        return 1
    fi
    
    # Check required parameters
    local required_vars=("NODE_ROLE" "STATE_DIR" "LOG_DIR" "K8S_VERSION" "POD_CIDR" "MASTER_IP")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required parameter $var is not set"
            return 1
        fi
    done
    
    # Validate IP addresses
    if ! validate_ip "$MASTER_IP"; then
        log_error "Invalid master IP address: $MASTER_IP"
        return 1
    fi
    
    # Validate CIDR
    if ! validate_cidr "$POD_CIDR"; then
        log_error "Invalid pod CIDR: $POD_CIDR"
        return 1
    fi
    
    # Check disk space (minimum 20GB)
    local available_space=$(df / | tail -1 | awk '{print $4}')
    local min_space=$((20 * 1024 * 1024))  # 20GB in KB
    
    if [[ $available_space -lt $min_space ]]; then
        log_error "Insufficient disk space. Required: 20GB, Available: $((available_space / 1024 / 1024))GB"
        return 1
    fi
    
    # Check memory (minimum 2GB)
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local min_memory=$((2 * 1024 * 1024))  # 2GB in KB
    
    if [[ $mem_total -lt $min_memory ]]; then
        log_error "Insufficient memory. Required: 2GB, Available: $((mem_total / 1024 / 1024))GB"
        return 1
    fi
    
    log_success "Environment validation passed"
    log_info "OS: $(get_os_info)"
    log_info "Memory: $(get_memory_info)"
    log_info "CPU: $(get_cpu_info)"
    
    return 0
}

# Initialize logging
init_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Create log file
    touch "$LOG_FILE"
    
    # Log session start
    echo "===============================================" >> "$LOG_FILE"
    echo "Kubernetes Setup Session Started" >> "$LOG_FILE"
    echo "Date: $(date)" >> "$LOG_FILE"
    echo "Host: $(hostname)" >> "$LOG_FILE"
    echo "User: $(whoami)" >> "$LOG_FILE"
    echo "Role: $NODE_ROLE" >> "$LOG_FILE"
    echo "===============================================" >> "$LOG_FILE"
}

# Export functions for use in main script
export -f log_info log_success log_warning log_error
export -f check_state mark_complete retry_command wait_for_service
export -f check_connectivity validate_ip validate_cidr
export -f get_os_info get_memory_info get_cpu_info validate_environment
export -f init_logging