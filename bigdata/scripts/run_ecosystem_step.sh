#!/bin/bash

# Hadoop Ecosystem step runner script
set -e

STEP="$1"
SCRIPT_DIR="$(dirname "$0")"

# Source utilities
source "${SCRIPT_DIR}/ecosystem_utils.sh"

# Initialize logging if not already done
if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="${LOG_DIR:-/tmp}/ecosystem-step.log"
    init_logging
fi

# System preparation
prepare_system() {
    log_info "=== System Preparation and Java Installation ==="

    # Kill conflicting processes
    log_info "Stopping conflicting services..."
    sudo systemctl stop unattended-upgrades || true
    sudo pkill -f "unattended-upgr" || true
    sudo pkill -f "apt-get" || true
    sudo pkill -f "dpkg" || true
    sleep 5

    # Remove locks
    log_info "Removing package locks..."
    sudo rm -f /var/lib/dpkg/lock*
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/apt/archives/lock

    # Fix dpkg
    log_info "Fixing dpkg configuration..."
    sudo dpkg --configure -a || true

    # Update system
    log_info "Updating system packages..."
    retry_command "sudo apt-get update" "$MAX_RETRIES"
    retry_command "sudo apt-get upgrade -y" "$MAX_RETRIES"

    # Install basic tools
    log_info "Installing basic tools..."
    retry_command "sudo apt-get install -y wget curl unzip zip python3 python3-pip build-essential git" "$MAX_RETRIES"

    # Install Java
    log_info "Installing Java OpenJDK $JAVA_VERSION..."
    retry_command "sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk openjdk-${JAVA_VERSION}-jre" "$MAX_RETRIES"

    # Set JAVA_HOME
    JAVA_HOME="/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64"
    set_environment "JAVA_HOME" "$JAVA_HOME"
    set_environment "PATH" "\$PATH:\$JAVA_HOME/bin"

    # Verify Java installation
    java -version

    # Create installation directories
    log_info "Creating installation directories..."
    sudo mkdir -p /opt/{hadoop,spark,hive,hbase,kafka,zookeeper,nifi,storm,flink,presto,drill,solr,elasticsearch,cassandra,mahout,sqoop,flume,oozie}
    sudo chown -R ubuntu:ubuntu /opt/

    # Create hadoop user
    create_user_if_not_exists "hadoop" "/home/hadoop"

    # Create data directories
    sudo mkdir -p /data/{hdfs,logs,tmp}
    sudo chown -R ubuntu:ubuntu /data/

    mark_complete "01_java_system"
    log_success "System preparation and Java installation completed"
}

# Core Hadoop installation
install_core_hadoop() {
    log_info "=== Installing Core Hadoop Ecosystem ==="

    # Install Hadoop
    log_info "Installing Hadoop $HADOOP_VERSION..."
    download_and_extract "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" "$HADOOP_HOME"
    set_environment "HADOOP_HOME" "$HADOOP_HOME"
    set_environment "HADOOP_CONF_DIR" "\$HADOOP_HOME/etc/hadoop"
    set_environment "PATH" "\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin"

    # Install Hive
    log_info "Installing Hive $HIVE_VERSION..."
    download_and_extract "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" "$HIVE_HOME"
    set_environment "HIVE_HOME" "$HIVE_HOME"
    set_environment "PATH" "\$PATH:\$HIVE_HOME/bin"

    # Install Sqoop
    log_info "Installing Sqoop $SQOOP_VERSION..."
    download_and_extract "https://archive.apache.org/dist/sqoop/${SQOOP_VERSION}/sqoop-${SQOOP_VERSION}.bin__hadoop-2.6.0.tar.gz" "$SQOOP_HOME"
    set_environment "SQOOP_HOME" "$SQOOP_HOME"
    set_environment "PATH" "\$PATH:\$SQOOP_HOME/bin"

    # Install Flume
    log_info "Installing Flume $FLUME_VERSION..."
    download_and_extract "https://archive.apache.org/dist/flume/${FLUME_VERSION}/apache-flume-${FLUME_VERSION}-bin.tar.gz" "$FLUME_HOME"
    set_environment "FLUME_HOME" "$FLUME_HOME"
    set_environment "PATH" "\$PATH:\$FLUME_HOME/bin"

    # Install Oozie
    log_info "Installing Oozie $OOZIE_VERSION..."
    download_and_extract "https://archive.apache.org/dist/oozie/${OOZIE_VERSION}/oozie-${OOZIE_VERSION}.tar.gz" "$OOZIE_HOME"
    set_environment "OOZIE_HOME" "$OOZIE_HOME"
    set_environment "PATH" "\$PATH:\$OOZIE_HOME/bin"

    mark_complete "02_core_hadoop"
    log_success "Core Hadoop ecosystem installation completed"
}

# Processing engines installation
install_processing_engines() {
    log_info "=== Installing Processing Engines ==="

    # Install Spark
    log_info "Installing Spark $SPARK_VERSION..."
    download_and_extract "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" "$SPARK_HOME"
    set_environment "SPARK_HOME" "$SPARK_HOME"
    set_environment "PATH" "\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin"

    # Install Flink
    log_info "Installing Flink $FLINK_VERSION..."
    download_and_extract "https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_2.12.tgz" "$FLINK_HOME"
    set_environment "FLINK_HOME" "$FLINK_HOME"
    set_environment "PATH" "\$PATH:\$FLINK_HOME/bin"

    # Install Presto
    log_info "Installing Presto $PRESTO_VERSION..."
    download_and_extract "https://repo1.maven.org/maven2/com/facebook/presto/presto-server/${PRESTO_VERSION}/presto-server-${PRESTO_VERSION}.tar.gz" "$PRESTO_HOME"
    set_environment "PRESTO_HOME" "$PRESTO_HOME"
    set_environment "PATH" "\$PATH:\$PRESTO_HOME/bin"

    # Install Drill
    log_info "Installing Drill $DRILL_VERSION..."
    download_and_extract "https://archive.apache.org/dist/drill/drill-${DRILL_VERSION}/apache-drill-${DRILL_VERSION}.tar.gz" "$DRILL_HOME"
    set_environment "DRILL_HOME" "$DRILL_HOME"
    set_environment "PATH" "\$PATH:\$DRILL_HOME/bin"

    # Install Mahout
    log_info "Installing Mahout $MAHOUT_VERSION..."
    download_and_extract "https://archive.apache.org/dist/mahout/${MAHOUT_VERSION}/apache-mahout-distribution-${MAHOUT_VERSION}.tar.gz" "$MAHOUT_HOME"
    set_environment "MAHOUT_HOME" "$MAHOUT_HOME"
    set_environment "PATH" "\$PATH:\$MAHOUT_HOME/bin"

    mark_complete "03_processing_engines"
    log_success "Processing engines installation completed"
}

# NoSQL databases installation
install_nosql_databases() {
    log_info "=== Installing NoSQL Databases ==="

    # Install HBase
    log_info "Installing HBase $HBASE_VERSION..."
    download_and_extract "https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz" "$HBASE_HOME"
    set_environment "HBASE_HOME" "$HBASE_HOME"
    set_environment "PATH" "\$PATH:\$HBASE_HOME/bin"

    # Install Cassandra
    log_info "Installing Cassandra $CASSANDRA_VERSION..."
    download_and_extract "https://archive.apache.org/dist/cassandra/${CASSANDRA_VERSION}/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz" "$CASSANDRA_HOME"
    set_environment "CASSANDRA_HOME" "$CASSANDRA_HOME"
    set_environment "PATH" "\$PATH:\$CASSANDRA_HOME/bin"

    # Install MongoDB
    log_info "Installing MongoDB $MONGODB_VERSION..."
    retry_command "wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | sudo apt-key add -" "$MAX_RETRIES"
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    retry_command "sudo apt-get update" "$MAX_RETRIES"
    retry_command "sudo apt-get install -y mongodb-org" "$MAX_RETRIES"

    mark_complete "04_nosql_databases"
    log_success "NoSQL databases installation completed"
}

# Streaming and messaging installation
install_streaming_messaging() {
    log_info "=== Installing Streaming & Messaging ==="

    # Install Zookeeper first (required for Kafka)
    log_info "Installing Zookeeper $ZOOKEEPER_VERSION..."
    download_and_extract "https://archive.apache.org/dist/zookeeper/zookeeper-${ZOOKEEPER_VERSION}/apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz" "$ZOOKEEPER_HOME"
    set_environment "ZOOKEEPER_HOME" "$ZOOKEEPER_HOME"
    set_environment "PATH" "\$PATH:\$ZOOKEEPER_HOME/bin"

    # Install Kafka
    log_info "Installing Kafka $KAFKA_VERSION..."
    download_and_extract "https://archive.apache.org/dist/kafka/3.5.1/kafka_${KAFKA_VERSION}.tgz" "$KAFKA_HOME"
    set_environment "KAFKA_HOME" "$KAFKA_HOME"
    set_environment "PATH" "\$PATH:\$KAFKA_HOME/bin"

    # Install NiFi
    log_info "Installing NiFi $NIFI_VERSION..."
    download_and_extract "https://archive.apache.org/dist/nifi/${NIFI_VERSION}/nifi-${NIFI_VERSION}-bin.tar.gz" "$NIFI_HOME"
    set_environment "NIFI_HOME" "$NIFI_HOME"
    set_environment "PATH" "\$PATH:\$NIFI_HOME/bin"

    # Install Storm
    log_info "Installing Storm $STORM_VERSION..."
    download_and_extract "https://archive.apache.org/dist/storm/apache-storm-${STORM_VERSION}/apache-storm-${STORM_VERSION}.tar.gz" "$STORM_HOME"
    set_environment "STORM_HOME" "$STORM_HOME"
    set_environment "PATH" "\$PATH:\$STORM_HOME/bin"

    mark_complete "05_streaming_messaging"
    log_success "Streaming & messaging installation completed"
}

# Search and indexing installation
install_search_indexing() {
    log_info "=== Installing Search & Indexing ==="

    # Install Solr
    log_info "Installing Solr $SOLR_VERSION..."
    download_and_extract "https://archive.apache.org/dist/lucene/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz" "$SOLR_HOME"
    set_environment "SOLR_HOME" "$SOLR_HOME"
    set_environment "PATH" "\$PATH:\$SOLR_HOME/bin"

    # Install Elasticsearch
    log_info "Installing Elasticsearch $ELASTICSEARCH_VERSION..."
    download_and_extract "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}-linux-x86_64.tar.gz" "$ELASTICSEARCH_HOME"
    set_environment "ELASTICSEARCH_HOME" "$ELASTICSEARCH_HOME"
    set_environment "PATH" "\$PATH:\$ELASTICSEARCH_HOME/bin"

    mark_complete "06_search_indexing"
    log_success "Search & indexing installation completed"
}

# Workflow orchestration installation
install_workflow_orchestration() {
    log_info "=== Installing Workflow & Orchestration ==="

    # Install Airflow using pip
    log_info "Installing Airflow $AIRFLOW_VERSION..."
    pip3 install --user apache-airflow==$AIRFLOW_VERSION

    # Initialize Airflow database
    export AIRFLOW_HOME=/home/ubuntu/airflow
    mkdir -p $AIRFLOW_HOME
    airflow db init

    # Create admin user
    airflow users create \
        --username admin \
        --password admin \
        --firstname Admin \
        --lastname User \
        --role Admin \
        --email admin@example.com

    mark_complete "07_workflow_orchestration"
    log_success "Workflow & orchestration installation completed"
}

# Configuration
configure_ecosystem() {
    log_info "=== Configuring Hadoop Ecosystem ==="

    # Source environment variables
    source /home/ubuntu/.bashrc

    # Configure Hadoop
    if [[ -d "$HADOOP_HOME" ]]; then
        log_info "Configuring Hadoop..."

        # Set JAVA_HOME in hadoop-env.sh
        echo "export JAVA_HOME=$JAVA_HOME" >> "$HADOOP_HOME/etc/hadoop/hadoop-env.sh"

        # Configure core-site.xml
        cat > "$HADOOP_HOME/etc/hadoop/core-site.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://${NAMENODE_HOST}:9000</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>/data/tmp</value>
    </property>
</configuration>
EOF

        # Configure hdfs-site.xml
        cat > "$HADOOP_HOME/etc/hadoop/hdfs-site.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>3</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>/data/hdfs/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>/data/hdfs/datanode</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>0.0.0.0:9870</value>
    </property>
</configuration>
EOF

        # Configure yarn-site.xml
        cat > "$HADOOP_HOME/etc/hadoop/yarn-site.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>yarn.resourcemanager.address</name>
        <value>${RESOURCEMANAGER_HOST}:8032</value>
    </property>
    <property>
        <name>yarn.resourcemanager.webapp.address</name>
        <value>0.0.0.0:8088</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>4096</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>4096</value>
    </property>
    <property>
        <name>yarn.scheduler.minimum-allocation-mb</name>
        <value>512</value>
    </property>
    <property>
        <name>yarn.nodemanager.vmem-check-enabled</name>
        <value>false</value>
    </property>
</configuration>
EOF

        # Configure mapred-site.xml
        cat > "$HADOOP_HOME/etc/hadoop/mapred-site.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value>
    </property>
</configuration>
EOF

        # Create data directories
        mkdir -p /data/hdfs/{namenode,datanode}
        mkdir -p /data/tmp

        log_success "Hadoop configuration completed"
    fi

    # Configure HBase if installed
    if [[ -d "$HBASE_HOME" ]]; then
        log_info "Configuring HBase..."

        # Configure hbase-site.xml
        cat > "$HBASE_HOME/conf/hbase-site.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>hbase.rootdir</name>
        <value>hdfs://${NAMENODE_HOST}:9000/hbase</value>
    </property>
    <property>
        <name>hbase.cluster.distributed</name>
        <value>true</value>
    </property>
    <property>
        <name>hbase.zookeeper.property.dataDir</name>
        <value>/data/zookeeper</value>
    </property>
    <property>
        <name>hbase.zookeeper.quorum</name>
        <value>${NAMENODE_HOST}</value>
    </property>
    <property>
        <name>hbase.master.info.port</name>
        <value>16010</value>
    </property>
</configuration>
EOF

        log_success "HBase configuration completed"
    fi

    # Configure Spark if installed
    if [[ -d "$SPARK_HOME" ]]; then
        log_info "Configuring Spark..."

        # Copy template and configure
        cp "$SPARK_HOME/conf/spark-env.sh.template" "$SPARK_HOME/conf/spark-env.sh"
        echo "export JAVA_HOME=$JAVA_HOME" >> "$SPARK_HOME/conf/spark-env.sh"
        echo "export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop" >> "$SPARK_HOME/conf/spark-env.sh"

        log_success "Spark configuration completed"
    fi

    mark_complete "08_configuration"
    log_success "Ecosystem configuration completed"
}

# Role-specific initialization
initialize_role() {
    log_info "=== Role-specific Initialization for $NODE_ROLE ==="

    case "$NODE_ROLE" in
        "namenode")
            initialize_namenode
            ;;
        "datanode")
            initialize_datanode
            ;;
        *)
            log_info "No specific initialization for role: $NODE_ROLE"
            ;;
    esac

    mark_complete "09_role_init"
    log_success "Role-specific initialization completed"
}

# Initialize NameNode
initialize_namenode() {
    log_info "Initializing NameNode..."

    # Format HDFS (only if not already formatted)
    if [[ ! -d "/data/hdfs/namenode/current" ]]; then
        log_info "Formatting HDFS..."
        "$HADOOP_HOME/bin/hdfs" namenode -format -force
        log_success "HDFS formatted successfully"
    else
        log_info "HDFS already formatted, skipping..."
    fi

    # Start Hadoop services
    log_info "Starting Hadoop services..."
    "$HADOOP_HOME/sbin/start-dfs.sh"
    "$HADOOP_HOME/sbin/start-yarn.sh"

    # Wait for services to start
    sleep 30

    # Verify services
    if check_port "localhost" "9870"; then
        log_success "NameNode web UI is accessible on port 9870"
    fi

    if check_port "localhost" "8088"; then
        log_success "ResourceManager web UI is accessible on port 8088"
    fi
}

# Initialize DataNode
initialize_datanode() {
    log_info "Initializing DataNode..."

    # DataNodes will automatically connect to NameNode
    log_info "DataNode will connect to NameNode at: $NAMENODE_HOST"

    # Start DataNode and NodeManager services will be started by NameNode
    log_success "DataNode initialization completed"
}

# Comprehensive verification
verify_full_ecosystem() {
    log_info "=== Full Ecosystem Verification ==="

    # Check Java
    if java -version 2>&1 | grep -q "openjdk"; then
        log_success "✅ Java is installed and working"
    else
        log_error "❌ Java is not working properly"
    fi

    # Check Hadoop
    if [[ -x "$HADOOP_HOME/bin/hadoop" ]]; then
        log_success "✅ Hadoop is installed"
        "$HADOOP_HOME/bin/hadoop" version | head -1 | tee -a "$LOG_FILE"
    else
        log_error "❌ Hadoop is not properly installed"
    fi

    # Check Spark
    if [[ -x "$SPARK_HOME/bin/spark-submit" ]]; then
        log_success "✅ Spark is installed"
        "$SPARK_HOME/bin/spark-submit" --version 2>&1 | head -1 | tee -a "$LOG_FILE"
    else
        log_warning "⚠️  Spark is not properly installed"
    fi

    # Check HBase
    if [[ -x "$HBASE_HOME/bin/hbase" ]]; then
        log_success "✅ HBase is installed"
        "$HBASE_HOME/bin/hbase" version 2>&1 | head -1 | tee -a "$LOG_FILE"
    else
        log_warning "⚠️  HBase is not properly installed"
    fi

    # Check Kafka
    if [[ -x "$KAFKA_HOME/bin/kafka-server-start.sh" ]]; then
        log_success "✅ Kafka is installed"
    else
        log_warning "⚠️  Kafka is not properly installed"
    fi

    # Check running services
    log_info "=== Running Java Processes ==="
    ps aux | grep java | grep -v grep | tee -a "$LOG_FILE" || log_info "No Java processes found"

    # Check ports
    log_info "=== Port Status ==="
    for port in 9870 8088 16010 9092 8080 8081; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_success "✅ Port $port: LISTENING"
        else
            log_info "ℹ️  Port $port: NOT LISTENING"
        fi
    done

    # System resources
    log_info "=== System Resources ==="
    log_info "Memory usage:"
    free -h | tee -a "$LOG_FILE"
    log_info "Disk usage:"
    df -h | tee -a "$LOG_FILE"
    log_info "Load average:"
    uptime | tee -a "$LOG_FILE"

    log_success "Ecosystem verification completed"
}

case "$STEP" in
    "prepare_system")
        prepare_system
        ;;
    "install_core_hadoop")
        install_core_hadoop
        ;;
    "install_processing_engines")
        install_processing_engines
        ;;
    "install_nosql_databases")
        install_nosql_databases
        ;;
    "install_streaming_messaging")
        install_streaming_messaging
        ;;
    "install_search_indexing")
        install_search_indexing
        ;;
    "install_workflow_orchestration")
        install_workflow_orchestration
        ;;
    "configure_ecosystem")
        configure_ecosystem
        ;;
    "initialize_role")
        initialize_role
        ;;
    "verify_full_ecosystem")
        verify_full_ecosystem
        ;;
    *)
        log_error "Unknown step: $STEP"
        exit 1
        ;;
esac