#!/bin/bash

set -e

echo "🔄 Starting replication setup..."

MAX_RETRIES=60
RETRY_DELAY=2
COUNT=0

# Wait until the migrations table exists on the master
echo "🕒 Waiting for migrations to complete on master..."
until mysql -h mysql -u root -ppassword -e "SELECT 1 FROM laravel.migrations LIMIT 1;" >/dev/null 2>&1; do
  echo "⏳ Migrations not ready on master..."
  sleep $RETRY_DELAY
done

# Wait until the master MySQL server is available and responding to SHOW MASTER STATUS
until MASTER_STATUS=$(mysql -h mysql -u root -ppassword -e "SHOW MASTER STATUS\G" 2>/dev/null); do
    echo "⏳ Waiting for SHOW MASTER STATUS to be available... ($COUNT/$MAX_RETRIES)"
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "❌ Timeout waiting for SHOW MASTER STATUS from master"
        exit 1
    fi
    sleep $RETRY_DELAY
done

LOG_FILE=$(echo "$MASTER_STATUS" | grep 'File:' | awk '{print $2}')
LOG_POS=$(echo "$MASTER_STATUS" | grep 'Position:' | awk '{print $2}')

if [ -z "$LOG_FILE" ] || [ -z "$LOG_POS" ]; then
    echo "❌ Failed to parse LOG_FILE or LOG_POS"
    exit 1
fi

echo "📄 Master log file: $LOG_FILE"
echo "📍 Master log position: $LOG_POS"

# Configure replication
mysql -u root -ppassword -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'mysql',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'replica',
  SOURCE_PASSWORD = 'replica_pass',
  SOURCE_LOG_FILE = '$LOG_FILE',
  SOURCE_LOG_POS = $LOG_POS;
START REPLICA;
"

echo "✅ Replication configured successfully with $LOG_FILE:$LOG_POS"
