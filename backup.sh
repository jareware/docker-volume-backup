#!/bin/bash

# Exit immediately on error
set -e

# Cronjobs don't inherit their env, so load from file
source env.sh

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

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

TIME_UPLOAD="0"
TIME_UPLOADED="0"
if [ ! -z "$BACKUP_BUCKET_NAME" ]; then
  info "Uploading backup"
  TIME_UPLOAD="$(date +%s.%N)"
  aws s3 cp --only-show-errors "$BACKUP_FILENAME" "s3://$BACKUP_BUCKET_NAME/"
  echo "Upload finished"
  TIME_UPLOADED="$(date +%s.%N)"
fi

info "Cleaning up"
rm -vf "$BACKUP_FILENAME"

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
