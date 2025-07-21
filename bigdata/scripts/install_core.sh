#!/bin/bash
# Core Hadoop components installer

source "$(dirname "$0")/ecosystem_utils.sh"

install_hadoop_core() {
    log_info "Installing Hadoop core components..."
    
    # This function is called from run_ecosystem_step.sh
    # Implementation is already in the main step runner
    
    return 0
}
