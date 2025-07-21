#!/bin/bash

# Main Hadoop Ecosystem setup script
# Exit on any error
set -e

# Parameters
NODE_ROLE="$1"
STATE_DIR="$2"
LOG_DIR="$3"
JAVA_VERSION="$4"
HADOOP_VERSION="$5"
MAX_RETRIES="$6"

# Validate parameters
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 <role> <state_dir> <log_dir> <java_version> <hadoop_version> <max_retries>"
    exit 1
fi

# Set up logging
LOG_FILE="${LOG_DIR}/$(hostname)-ecosystem-setup.log"
mkdir -p "$LOG_DIR"

# Source utilities
SCRIPT_DIR="$(dirname "$0")"
if [[ -f "${SCRIPT_DIR}/ecosystem_utils.sh" ]]; then
    source "${SCRIPT_DIR}/ecosystem_utils.sh"
else
    echo "ERROR: ecosystem_utils.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# Initialize logging
init_logging

# Main execution
main() {
    log_info "Starting Hadoop Ecosystem setup for ${NODE_ROLE} node"
    log_info "Parameters: Role=$NODE_ROLE, JAVA_VERSION=$JAVA_VERSION, HADOOP_VERSION=$HADOOP_VERSION"
    
    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        exit 1
    fi
    
    log_success "Hadoop Ecosystem setup completed successfully!"
    return 0
}

# Run main function
main "$@"
