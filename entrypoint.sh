#!/bin/bash

# Exit immediately on error
set -e

# Write cronjob env to file, fill in sensible defaults, and read them back in
cat <<EOF > env.sh
BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_CRON_EXPRESSION="${BACKUP_CRON_EXPRESSION:-@daily}"
AWS_S3_BUCKET_NAME="${AWS_S3_BUCKET_NAME:-}"
BACKUP_FILENAME="$(date +"${BACKUP_FILENAME:-backup-%F.tar.gz}")"
BACKUP_ARCHIVE="${BACKUP_ARCHIVE}"
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
DOCKER_STOP_OPT_IN_LABEL="${DOCKER_STOP_OPT_IN_LABEL:-docker-volume-backup-companion.stop-during-backup}"
INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"
EOF
chmod a+x env.sh
source env.sh

# Configure AWS CLI
mkdir .aws
cat <<EOF > .aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF
cat <<EOF > .aws/config
[default]
region = ${AWS_DEFAULT_REGION}
EOF

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry: docker-volume-backup-companion"
echo "$BACKUP_CRON_EXPRESSION root /root/backup.sh > /proc/1/fd/1 2>&1" > /etc/cron.d/docker-volume-backup-companion

# Let cron take the wheel
echo "Starting cron in foreground with expression: $BACKUP_CRON_EXPRESSION"
cron -f
