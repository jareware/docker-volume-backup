#!/bin/bash

# Exit immediately on error
set -e

# Set defaults for any missing environment variables
BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_FILENAME="${BACKUP_FILENAME:-latest.tar.gz}"
BACKUP_PERIOD_SECONDS="${BACKUP_PERIOD_SECONDS:-86400}" # i.e. every 24 hours
BACKUP_UPLOAD_WAIT_SECONDS="${BACKUP_UPLOAD_WAIT_SECONDS:-30}" # to wait out the load spike of starting the containers back up
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
DOCKER_STOP_OPT_IN_LABEL="${DOCKER_STOP_OPT_IN_LABEL:-docker-volume-backup-companion.stop-during-backup}"
INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1\n$reset"
}

info "Backup sleeping"
echo "Sleeping $BACKUP_PERIOD_SECONDS seconds..."
sleep "$BACKUP_PERIOD_SECONDS"

info "Backup starting"
TIME_START="$(date +%s.%N)"
CONTAINERS_TO_STOP="$(docker ps --format "{{.ID}}" --filter "label=$DOCKER_STOP_OPT_IN_LABEL=true" | tr '\n' ' ')"
CONTAINERS_TOTAL="$(docker ps --format "{{.ID}}" | wc -l)"
echo "$CONTAINERS_TOTAL containers running"

if [[ ! "$CONTAINERS_TO_STOP" =~ ^\ *$ ]]; then
  info "Stopping containers"
  TEMPFILE="$(mktemp)"
  docker stop $CONTAINERS_TO_STOP | tee "$TEMPFILE"
  CONTAINERS_STOPPED="$(cat $TEMPFILE | wc -l)"
  rm "$TEMPFILE"
fi
CONTAINERS_STOPPED=${CONTAINERS_STOPPED:-0}

info "Creating backup"
TIME_BACK_UP="$(date +%s.%N)"
tar -czvf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
BACKUP_SIZE="$(du --bytes $BACKUP_FILENAME | sed 's/\s.*$//')"
TIME_BACKED_UP="$(date +%s.%N)"

if [[ ! "$CONTAINERS_TO_STOP" =~ ^\ *$ ]]; then
  info "Starting containers"
  docker start $CONTAINERS_TO_STOP
fi

info "Waiting before upload"
echo "Sleeping $BACKUP_UPLOAD_WAIT_SECONDS seconds..."
sleep "$BACKUP_UPLOAD_WAIT_SECONDS"

info "Uploading backup"
TIME_UPLOAD="$(date +%s.%N)"
aws s3 cp --only-show-errors "$BACKUP_FILENAME" "s3://$BACKUP_BUCKET_NAME/"
echo "Upload finished"
TIME_UPLOADED="$(date +%s.%N)"

info "Cleaning up"
rm -v "$BACKUP_FILENAME"

TIME_FINISH="$(date +%s.%N)"
INFLUX_LINE="$INFLUXDB_MEASUREMENT\
,host=$BACKUP_HOSTNAME\
\
 size_compressed_bytes=$BACKUP_SIZE\
,containers_total=$CONTAINERS_TOTAL\
,containers_stopped=$CONTAINERS_STOPPED\
,time_wall=$(perl -E "say $TIME_FINISH - $TIME_START")\
,time_total=$(perl -E "say $TIME_FINISH - $TIME_START - $BACKUP_UPLOAD_WAIT_SECONDS")\
,time_compress=$(perl -E "say $TIME_BACKED_UP - $TIME_BACK_UP")\
,time_upload=$(perl -E "say $TIME_UPLOADED - $TIME_UPLOAD")\
"
if [ ! -z "$INFLUXDB_URL" ]; then
  info "Shipping metrics"
  echo "$INFLUX_LINE" | tr , '\n'
  echo
  curl \
    --silent \
    --include \
    --request POST \
    --user "$INFLUXDB_CREDENTIALS" \
    "$INFLUXDB_URL/write?db=$INFLUXDB_DB" \
    --data-binary "$INFLUX_LINE"
fi

info "Backup finished"
echo "Script will now exit"
