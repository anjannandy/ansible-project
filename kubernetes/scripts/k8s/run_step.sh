#!/bin/bash

# Kubernetes Setup Step Runner
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

# Initialize logging
init_logging

# Main function
main() {
    local step="${1:-}"

    if [[ -z "$step" ]]; then
        log_error "Usage: $0 <step_name>"
        echo "Available steps:"
        echo "  system_prep"
        echo "  install_docker"
        echo "  install_kubernetes"
        echo "  configure_system"
        echo "  initialize_master"
        echo "  join_worker"
        echo "  install_cni"
        echo "  verify_installation"
        exit 1
    fi

    log_info "Starting step: $step"
    log_info "Node role: ${NODE_ROLE:-unknown}"
    log_info "System info:"
    get_system_info

    # Set timeout for the entire step
    local timeout="${STEP_TIMEOUT:-1800}"  # 30 minutes default

    # Run the step with timeout
    if timeout "$timeout" bash "${SCRIPT_DIR}/setup_k8s.sh" "$step"; then
        log_success "Step $step completed successfully"
        exit 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Step $step timed out after $timeout seconds"
        else
            log_error "Step $step failed with exit code $exit_code"
        fi
        exit $exit_code
    fi
}

# Trap signals and cleanup
cleanup() {
    log_warning "Script interrupted, cleaning up..."
}

trap cleanup SIGTERM SIGINT

# Run main function
main "$@"