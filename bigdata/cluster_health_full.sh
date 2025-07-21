#!/bin/bash

# Comprehensive cluster health check script
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==============================================="
echo " HADOOP ECOSYSTEM CLUSTER HEALTH CHECK"
echo "==============================================="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Check Java
echo "=== Java Version ==="
if command -v java &> /dev/null; then
    java -version 2>&1
    echo "✅ Java is available"
else
    echo "❌ Java is not installed"
fi
echo ""

# Check Hadoop
echo "=== Hadoop Status ==="
if [[ -n "$HADOOP_HOME" ]] && [[ -x "$HADOOP_HOME/bin/hadoop" ]]; then
    echo "Hadoop Version:"
    "$HADOOP_HOME/bin/hadoop" version | head -5
    echo ""
    
    echo "HDFS Status:"
    if "$HADOOP_HOME/bin/hdfs" dfsadmin -report 2>/dev/null; then
        echo "✅ HDFS is running"
    else
        echo "⚠️  HDFS not running or not accessible"
    fi
    echo ""
    
    echo "YARN Status:"
    if "$HADOOP_HOME/bin/yarn" node -list 2>/dev/null; then
        echo "✅ YARN is running"
    else
        echo "⚠️  YARN not running or not accessible"
    fi
else
    echo "❌ Hadoop not found or not configured properly"
    echo "HADOOP_HOME: ${HADOOP_HOME:-'Not set'}"
fi
echo ""

# Check Spark
echo "=== Spark Status ==="
if [[ -n "$SPARK_HOME" ]] && [[ -x "$SPARK_HOME/bin/spark-submit" ]]; then
    echo "Spark Version:"
    "$SPARK_HOME/bin/spark-submit" --version 2>&1 | head -3
    echo "✅ Spark is available"
else
    echo "❌ Spark not found or not configured"
    echo "SPARK_HOME: ${SPARK_HOME:-'Not set'}"
fi
echo ""

# Check HBase
echo "=== HBase Status ==="
if [[ -n "$HBASE_HOME" ]] && [[ -x "$HBASE_HOME/bin/hbase" ]]; then
    echo "HBase Version:"
    "$HBASE_HOME/bin/hbase" version 2>&1 | head -3
    echo "✅ HBase is available"
else
    echo "❌ HBase not found or not configured"
    echo "HBASE_HOME: ${HBASE_HOME:-'Not set'}"
fi
echo ""

# Check Kafka
echo "=== Kafka Status ==="
if [[ -n "$KAFKA_HOME" ]] && [[ -d "$KAFKA_HOME" ]]; then
    echo "Kafka Location: $KAFKA_HOME"
    if [[ -x "$KAFKA_HOME/bin/kafka-server-start.sh" ]]; then
        echo "✅ Kafka binaries are available"
    else
        echo "⚠️  Kafka binaries not executable"
    fi
else
    echo "❌ Kafka not found or not configured"
    echo "KAFKA_HOME: ${KAFKA_HOME:-'Not set'}"
fi
echo ""

# Check Zookeeper
echo "=== Zookeeper Status ==="
if [[ -n "$ZOOKEEPER_HOME" ]] && [[ -d "$ZOOKEEPER_HOME" ]]; then
    echo "Zookeeper Location: $ZOOKEEPER_HOME"
    echo "✅ Zookeeper is available"
else
    echo "❌ Zookeeper not found or not configured"
fi
echo ""

# Check running processes
echo "=== Running Big Data Processes ==="
echo "Java processes related to Hadoop ecosystem:"
ps aux | grep -E "(hadoop|spark|hbase|kafka|zookeeper|hive|storm|flink)" | grep java | grep -v grep | while read line; do
    echo "   $line"
done
echo ""

# Check ports
echo "=== Network Port Status ==="
echo "Checking common big data ports:"

declare -A ports=(
    ["9870"]="Hadoop NameNode Web UI"
    ["8088"]="YARN ResourceManager Web UI"
    ["16010"]="HBase Master Web UI"
    ["9092"]="Kafka Broker"
    ["8080"]="Spark Master Web UI"
    ["8081"]="Spark Worker Web UI"
    ["2181"]="Zookeeper"
    ["9200"]="Elasticsearch HTTP"
    ["8983"]="Solr"
    ["8020"]="Hadoop NameNode IPC"
    ["50070"]="Hadoop NameNode Web UI (old)"
    ["10000"]="Hive Server2"
)

for port in "${!ports[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "  ✅ Port $port (${ports[$port]}): LISTENING"
    else
        echo "  ⚪ Port $port (${ports[$port]}): NOT LISTENING"
    fi
done
echo ""

# Check disk space for data directories
echo "=== Data Directory Disk Usage ==="
if [[ -d "/data" ]]; then
    echo "Data directory usage:"
    du -sh /data/* 2>/dev/null || echo "  No data directories found"
    echo ""
    echo "Available space in /data:"
    df -h /data 2>/dev/null || echo "  /data directory not found"
else
    echo "⚠️  /data directory not found"
fi
echo ""

# System resources
echo "=== System Resources ==="
echo "Memory Usage:"
free -h
echo ""
echo "CPU Load:"
uptime
echo ""
echo "Disk Usage (all mounted filesystems):"
df -h
echo ""

# Check environment variables
echo "=== Environment Variables ==="
echo "Key environment variables for big data ecosystem:"
env | grep -E "(JAVA_HOME|HADOOP|SPARK|HBASE|KAFKA|ZOOKEEPER|HIVE)" | sort
echo ""

# Network connectivity test
echo "=== Network Connectivity ==="
if command -v nc &> /dev/null; then
    echo "Testing connectivity to common ports on localhost:"
    for port in 9870 8088 16010; do
        if timeout 2 nc -z localhost $port 2>/dev/null; then
            echo "  ✅ localhost:$port is reachable"
        else
            echo "  ❌ localhost:$port is not reachable"
        fi
    done
else
    echo "⚠️  netcat (nc) not available for connectivity testing"
fi
echo ""

echo "==============================================="
echo " HEALTH CHECK COMPLETED"
echo "==============================================="
echo "Summary:"
echo "- Java: $(command -v java >/dev/null && echo '✅ Available' || echo '❌ Missing')"
echo "- Hadoop: $([[ -n "$HADOOP_HOME" ]] && [[ -x "$HADOOP_HOME/bin/hadoop" ]] && echo '✅ Configured' || echo '❌ Not configured')"
echo "- Spark: $([[ -n "$SPARK_HOME" ]] && [[ -x "$SPARK_HOME/bin/spark-submit" ]] && echo '✅ Configured' || echo '❌ Not configured')"
echo "- HBase: $([[ -n "$HBASE_HOME" ]] && [[ -x "$HBASE_HOME/bin/hbase" ]] && echo '✅ Configured' || echo '❌ Not configured')"
echo "- Kafka: $([[ -n "$KAFKA_HOME" ]] && [[ -d "$KAFKA_HOME" ]] && echo '✅ Configured' || echo '❌ Not configured')"
echo ""
echo "For detailed logs, check: /home/ubuntu/hadoop-setup-logs/"
echo "==============================================="
