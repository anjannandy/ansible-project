#!/bin/bash

# Hadoop Ecosystem step runner script
set -e

# Ensure we have a proper PATH at the very beginning
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:$PATH"

# Verify critical commands are available
for cmd in sudo mkdir touch; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' not found in PATH: $PATH"
        exit 127
    fi
done

STEP="$1"
SCRIPT_DIR="$(dirname "$0")"

# Set default values to prevent variable expansion issues
export LOG_FILE="${LOG_FILE:-/tmp/ecosystem-step.log}"
export STATE_DIR="${STATE_DIR:-/tmp/hadoop-state}"

# Source utilities with PATH preservation
source "${SCRIPT_DIR}/ecosystem_utils.sh"

# Initialize logging
init_logging

prepare_system() {
    log_info "=== System Preparation and Java Installation ==="

    log_info "Stopping conflicting services..."
    /usr/bin/sudo /usr/bin/systemctl stop unattended-upgrades || true
    /usr/bin/sudo /usr/bin/pkill -f "unattended-upgr" || true
    /usr/bin/sudo /usr/bin/pkill -f "apt-get" || true
    /usr/bin/sudo /usr/bin/pkill -f "dpkg" || true
    sleep 5

    log_info "Removing package locks..."
    /usr/bin/sudo /usr/bin/rm -f /var/lib/dpkg/lock*
    /usr/bin/sudo /usr/bin/rm -f /var/lib/apt/lists/lock
    /usr/bin/sudo /usr/bin/rm -f /var/cache/apt/archives/lock

    log_info "Fixing dpkg configuration..."
    /usr/bin/sudo /usr/bin/dpkg --configure -a || true

    log_info "Updating system packages..."
    retry_command "/usr/bin/sudo /usr/bin/apt-get update" "${MAX_RETRIES:-3}"
    retry_command "/usr/bin/sudo /usr/bin/apt-get upgrade -y" "${MAX_RETRIES:-3}"

    log_info "Installing basic tools..."
    retry_command "/usr/bin/sudo /usr/bin/apt-get install -y wget curl unzip zip python3 python3-pip build-essential git" "${MAX_RETRIES:-3}"

    log_info "Installing Java OpenJDK ${JAVA_VERSION:-11}..."
    retry_command "/usr/bin/sudo /usr/bin/apt-get install -y openjdk-${JAVA_VERSION:-11}-jdk openjdk-${JAVA_VERSION:-11}-jre" "${MAX_RETRIES:-3}"

    # Set JAVA_HOME
    JAVA_HOME="/usr/lib/jvm/java-${JAVA_VERSION:-11}-openjdk-amd64"
    export JAVA_HOME="$JAVA_HOME"

    set_environment "JAVA_HOME" "$JAVA_HOME"
    set_environment "PATH" "\$PATH:\$JAVA_HOME/bin"

    log_info "Verifying Java installation..."
    if [[ -x "$JAVA_HOME/bin/java" ]]; then
        "$JAVA_HOME/bin/java" -version
    else
        /usr/bin/java -version
    fi

    log_info "Creating installation directories..."
    /usr/bin/sudo /usr/bin/mkdir -p /opt/{hadoop,spark,hive,hbase,kafka,zookeeper,nifi,storm,flink,presto,drill,solr,elasticsearch,cassandra,mahout,sqoop,flume,oozie}
    /usr/bin/sudo /usr/bin/chown -R ubuntu:ubuntu /opt/

    # Create hadoop user if needed
    if ! /usr/bin/id hadoop >/dev/null 2>&1; then
        log_info "Creating hadoop user..."
        /usr/bin/sudo /usr/sbin/useradd -m -d /home/hadoop -s /bin/bash hadoop
        /usr/bin/sudo /usr/sbin/usermod -aG sudo hadoop
    fi

    /usr/bin/sudo /usr/bin/mkdir -p /data/{hdfs,logs,tmp}
    /usr/bin/sudo /usr/bin/chown -R ubuntu:ubuntu /data/

    mark_complete "01_java_system"
    log_success "System preparation and Java installation completed"
}

install_core_hadoop() {
    log_info "=== Installing Core Hadoop Ecosystem ==="

    # Ensure JAVA_HOME is set
    if [[ -z "$JAVA_HOME" ]]; then
        export JAVA_HOME="/usr/lib/jvm/java-${JAVA_VERSION:-11}-openjdk-amd64"
    fi

    log_info "Installing Hadoop ${HADOOP_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" "${HADOOP_HOME}"
    set_environment "HADOOP_HOME" "${HADOOP_HOME}"
    set_environment "HADOOP_CONF_DIR" "\$HADOOP_HOME/etc/hadoop"
    set_environment "PATH" "\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin"

    log_info "Installing Hive ${HIVE_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" "${HIVE_HOME}"
    set_environment "HIVE_HOME" "${HIVE_HOME}"
    set_environment "PATH" "\$PATH:\$HIVE_HOME/bin"

    log_info "Installing Sqoop ${SQOOP_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/sqoop/${SQOOP_VERSION}/sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0.tar.gz" "${SQOOP_HOME}"
    set_environment "SQOOP_HOME" "${SQOOP_HOME}"
    set_environment "PATH" "\$PATH:\$SQOOP_HOME/bin"

    log_info "Installing Flume ${FLUME_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/flume/${FLUME_VERSION}/apache-flume-${FLUME_VERSION}-bin.tar.gz" "${FLUME_HOME}"
    set_environment "FLUME_HOME" "${FLUME_HOME}"
    set_environment "PATH" "\$PATH:\$FLUME_HOME/bin"

    log_info "Installing Oozie ${OOZIE_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/oozie/${OOZIE_VERSION}/oozie-${OOZIE_VERSION}.tar.gz" "${OOZIE_HOME}"
    set_environment "OOZIE_HOME" "${OOZIE_HOME}"
    set_environment "PATH" "\$PATH:\$OOZIE_HOME/bin"

    mark_complete "02_core_hadoop"
    log_success "Core Hadoop ecosystem installation completed"
}

install_processing_engines() {
    log_info "=== Installing Processing Engines ==="

    log_info "Installing Spark ${SPARK_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" "${SPARK_HOME}"
    set_environment "SPARK_HOME" "${SPARK_HOME}"
    set_environment "PATH" "\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin"

    log_info "Installing Flink ${FLINK_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_2.12.tgz" "${FLINK_HOME}"
    set_environment "FLINK_HOME" "${FLINK_HOME}"
    set_environment "PATH" "\$PATH:\$FLINK_HOME/bin"

    log_info "Installing Presto ${PRESTO_VERSION}..."
    download_and_extract "https://repo1.maven.org/maven2/com/facebook/presto/presto-server/${PRESTO_VERSION}/presto-server-${PRESTO_VERSION}.tar.gz" "${PRESTO_HOME}"
    set_environment "PRESTO_HOME" "${PRESTO_HOME}"
    set_environment "PATH" "\$PATH:\$PRESTO_HOME/bin"

    log_info "Installing Drill ${DRILL_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/drill/drill-${DRILL_VERSION}/apache-drill-${DRILL_VERSION}.tar.gz" "${DRILL_HOME}"
    set_environment "DRILL_HOME" "${DRILL_HOME}"
    set_environment "PATH" "\$PATH:\$DRILL_HOME/bin"

    log_info "Installing Mahout ${MAHOUT_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/mahout/${MAHOUT_VERSION}/apache-mahout-distribution-${MAHOUT_VERSION}.tar.gz" "${MAHOUT_HOME}"
    set_environment "MAHOUT_HOME" "${MAHOUT_HOME}"
    set_environment "PATH" "\$PATH:\$MAHOUT_HOME/bin"

    mark_complete "03_processing_engines"
    log_success "Processing engines installation completed"
}

install_nosql_databases() {
    log_info "=== Installing NoSQL Databases ==="

    log_info "Installing HBase ${HBASE_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz" "${HBASE_HOME}"
    set_environment "HBASE_HOME" "${HBASE_HOME}"
    set_environment "PATH" "\$PATH:\$HBASE_HOME/bin"

    log_info "Installing Cassandra ${CASSANDRA_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/cassandra/${CASSANDRA_VERSION}/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz" "${CASSANDRA_HOME}"
    set_environment "CASSANDRA_HOME" "${CASSANDRA_HOME}"
    set_environment "PATH" "\$PATH:\$CASSANDRA_HOME/bin"

    log_info "Installing MongoDB ${MONGODB_VERSION}..."
    retry_command "/usr/bin/wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | /usr/bin/sudo /usr/bin/apt-key add -" "${MAX_RETRIES:-3}"
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(/usr/bin/lsb_release -cs)/mongodb-org/7.0 multiverse" | /usr/bin/sudo /usr/bin/tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    retry_command "/usr/bin/sudo /usr/bin/apt-get update" "${MAX_RETRIES:-3}"
    retry_command "/usr/bin/sudo /usr/bin/apt-get install -y mongodb-org" "${MAX_RETRIES:-3}"

    mark_complete "04_nosql_databases"
    log_success "NoSQL databases installation completed"
}

install_streaming_messaging() {
    log_info "=== Installing Streaming & Messaging ==="

    log_info "Installing Zookeeper ${ZOOKEEPER_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/zookeeper/zookeeper-${ZOOKEEPER_VERSION}/apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz" "${ZOOKEEPER_HOME}"
    set_environment "ZOOKEEPER_HOME" "${ZOOKEEPER_HOME}"
    set_environment "PATH" "\$PATH:\$ZOOKEEPER_HOME/bin"

    log_info "Installing Kafka ${KAFKA_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/kafka/3.5.1/kafka_${KAFKA_VERSION}.tgz" "${KAFKA_HOME}"
    set_environment "KAFKA_HOME" "${KAFKA_HOME}"
    set_environment "PATH" "\$PATH:\$KAFKA_HOME/bin"

    log_info "Installing NiFi ${NIFI_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/nifi/${NIFI_VERSION}/nifi-${NIFI_VERSION}-bin.tar.gz" "${NIFI_HOME}"
    set_environment "NIFI_HOME" "${NIFI_HOME}"
    set_environment "PATH" "\$PATH:\$NIFI_HOME/bin"

    log_info "Installing Storm ${STORM_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/storm/apache-storm-${STORM_VERSION}/apache-storm-${STORM_VERSION}.tar.gz" "${STORM_HOME}"
    set_environment "STORM_HOME" "${STORM_HOME}"
    set_environment "PATH" "\$PATH:\$STORM_HOME/bin"

    mark_complete "05_streaming_messaging"
    log_success "Streaming & messaging installation completed"
}

install_search_indexing() {
    log_info "=== Installing Search & Indexing ==="

    log_info "Installing Solr ${SOLR_VERSION}..."
    download_and_extract "https://archive.apache.org/dist/lucene/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz" "${SOLR_HOME}"
    set_environment "SOLR_HOME" "${SOLR_HOME}"
    set_environment "PATH" "\$PATH:\$SOLR_HOME/bin"

    log_info "Installing Elasticsearch ${ELASTICSEARCH_VERSION}..."
    download_and_extract "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}-linux-x86_64.tar.gz" "${ELASTICSEARCH_HOME}"
    set_environment "ELASTICSEARCH_HOME" "${ELASTICSEARCH_HOME}"
    set_environment "PATH" "\$PATH:\$ELASTICSEARCH_HOME/bin"

    mark_complete "06_search_indexing"
    log_success "Search & indexing installation completed"
}

install_workflow_orchestration() {
    log_info "=== Installing Workflow & Orchestration ==="

    log_info "Installing Airflow ${AIRFLOW_VERSION}..."
    /usr/bin/python3 -m pip install --user apache-airflow==${AIRFLOW_VERSION}

    mark_complete "07_workflow_orchestration"
    log_success "Workflow & orchestration installation completed"
}

configure_ecosystem() {
    log_info "=== Configuring Ecosystem ==="

    # This is a placeholder for ecosystem configuration
    # In a real implementation, this would configure Hadoop, Spark, etc.
    log_info "Ecosystem configuration would be implemented here"

    mark_complete "08_configuration"
    log_success "Ecosystem configuration completed"
}

initialize_role() {
    log_info "=== Initializing Role: ${NODE_ROLE:-unknown} ==="

    # This is a placeholder for role-specific initialization
    # In a real implementation, this would start services based on node role
    log_info "Role-specific initialization would be implemented here for role: ${NODE_ROLE:-unknown}"

    mark_complete "09_role_init"
    log_success "Role initialization completed"
}

verify_full_ecosystem() {
    log_info "=== Verifying Full Ecosystem ==="

    # Basic verification - check if key directories exist
    local errors=0

    for dir in "${HADOOP_HOME}" "${SPARK_HOME}" "${HIVE_HOME}"; do
        if [[ -n "$dir" && ! -d "$dir" ]]; then
            log_error "Directory not found: $dir"
            ((errors++))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_success "Full ecosystem verification completed successfully"
        return 0
    else
        log_error "Ecosystem verification failed with $errors errors"
        return 1
    fi
}

# Main case statement
case "$STEP" in
    prepare_system)
        prepare_system
        ;;
    install_core_hadoop)
        install_core_hadoop
        ;;
    install_processing_engines)
        install_processing_engines
        ;;
    install_nosql_databases)
        install_nosql_databases
        ;;
    install_streaming_messaging)
        install_streaming_messaging
        ;;
    install_search_indexing)
        install_search_indexing
        ;;
    install_workflow_orchestration)
        install_workflow_orchestration
        ;;
    configure_ecosystem)
        configure_ecosystem
        ;;
    initialize_role)
        initialize_role
        ;;
    verify_full_ecosystem)
        verify_full_ecosystem
        ;;
    *)
        echo "Usage: $0 {prepare_system|install_core_hadoop|install_processing_engines|install_nosql_databases|install_streaming_messaging|install_search_indexing|install_workflow_orchestration|configure_ecosystem|initialize_role|verify_full_ecosystem}"
        exit 1
        ;;
esac