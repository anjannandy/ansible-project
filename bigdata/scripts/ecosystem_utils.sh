#!/bin/bash

# Hadoop Ecosystem Utilities

# Ensure we have a proper PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Simple timestamp function
get_timestamp() {
    if command -v date >/dev/null 2>&1; then
        /usr/bin/date '+%Y-%m-%d %H:%M:%S'
    else
        echo "timestamp-unavailable"
    fi
}

# Simplified logging functions
log_info() {
    local timestamp
    timestamp=$(get_timestamp)
    local message="${BLUE}[INFO]${NC} ${timestamp} $1"
    echo -e "$message"

    # Try to append to log file if possible and LOG_FILE is reasonable
    if [[ -n "$LOG_FILE" && ${#LOG_FILE} -lt 1000 ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_success() {
    local timestamp
    timestamp=$(get_timestamp)
    local message="${GREEN}[SUCCESS]${NC} ${timestamp} $1"
    echo -e "$message"

    if [[ -n "$LOG_FILE" && ${#LOG_FILE} -lt 1000 ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_warning() {
    local timestamp
    timestamp=$(get_timestamp)
    local message="${YELLOW}[WARNING]${NC} ${timestamp} $1"
    echo -e "$message"

    if [[ -n "$LOG_FILE" && ${#LOG_FILE} -lt 1000 ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_error() {
    local timestamp
    timestamp=$(get_timestamp)
    local message="${RED}[ERROR]${NC} ${timestamp} $1"
    echo -e "$message"

    if [[ -n "$LOG_FILE" && ${#LOG_FILE} -lt 1000 ]]; then
        echo -e "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Initialize logging
init_logging() {
    # Set a safe default if LOG_FILE is not set or too large
    if [[ -z "$LOG_FILE" || ${#LOG_FILE} -gt 1000 ]]; then
        LOG_FILE="/tmp/ecosystem-setup.log"
    fi

    # Ensure log directory exists
    local log_dir
    log_dir=$(/usr/bin/dirname "$LOG_FILE" 2>/dev/null) || log_dir="/tmp"

    if [[ ! -d "$log_dir" ]]; then
        /usr/bin/mkdir -p "$log_dir" 2>/dev/null || LOG_FILE="/tmp/ecosystem-setup.log"
    fi

    # Write log header
    {
        echo "================================================================"
        echo "Hadoop Ecosystem Setup Log for $(/usr/bin/hostname 2>/dev/null || echo 'unknown-host')"
        echo "Started: $(get_timestamp)"
        echo "Role: ${NODE_ROLE:-unknown}"
        echo "================================================================"
        echo ""
    } > "$LOG_FILE" 2>/dev/null || true
}

# Check state
check_state() {
    local step="$1"
    [[ -f "${STATE_DIR}/${step}_completed" ]]
}

# Mark step complete
mark_complete() {
    local step="$1"

    # Set safe default if STATE_DIR is not set
    if [[ -z "$STATE_DIR" ]]; then
        STATE_DIR="/tmp/hadoop-state"
    fi

    /usr/bin/mkdir -p "$STATE_DIR" 2>/dev/null || {
        log_error "Cannot create state directory: $STATE_DIR"
        return 1
    }

    if /usr/bin/touch "${STATE_DIR}/${step}_completed" 2>/dev/null; then
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

# Download and extract archive
download_and_extract() {
    local url="$1"
    local dest_dir="$2"
    local archive_name
    archive_name=$(/usr/bin/basename "$url")
    local temp_dir="/tmp/hadoop-downloads"

    /usr/bin/mkdir -p "$temp_dir"

    log_info "Downloading $archive_name..."
    if ! /usr/bin/curl -L -o "$temp_dir/$archive_name" "$url"; then
        log_error "Failed to download $archive_name"
        return 1
    fi

    log_info "Extracting $archive_name to $dest_dir..."
    /usr/bin/sudo /usr/bin/mkdir -p "$dest_dir"

    if [[ "$archive_name" == *.tar.gz ]] || [[ "$archive_name" == *.tgz ]]; then
        /usr/bin/sudo /usr/bin/tar -xzf "$temp_dir/$archive_name" -C "$dest_dir" --strip-components=1
    elif [[ "$archive_name" == *.tar ]]; then
        /usr/bin/sudo /usr/bin/tar -xf "$temp_dir/$archive_name" -C "$dest_dir" --strip-components=1
    elif [[ "$archive_name" == *.zip ]]; then
        /usr/bin/sudo /usr/bin/unzip -q "$temp_dir/$archive_name" -d "$temp_dir/extract"
        /usr/bin/sudo /usr/bin/cp -r "$temp_dir/extract"/*/* "$dest_dir/"
    else
        log_error "Unsupported archive format: $archive_name"
        return 1
    fi

    /usr/bin/sudo /usr/bin/chown -R ubuntu:ubuntu "$dest_dir"
    /usr/bin/rm -f "$temp_dir/$archive_name"

    log_success "$archive_name extracted successfully"
}

# Set environment variables
set_environment() {
    local var_name="$1"
    local var_value="$2"
    local profile_file="/home/ubuntu/.bashrc"

    if ! /usr/bin/grep -q "export ${var_name}=" "$profile_file" 2>/dev/null; then
        echo "export ${var_name}=${var_value}" >> "$profile_file"
        log_info "Added $var_name to environment"
    fi

    export "$var_name"="$var_value"
}