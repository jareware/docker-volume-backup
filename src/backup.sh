#!/bin/bash

# Cronjobs don't inherit their env, so load from file
source env.sh

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

info "Backup starting"
TIME_START="$(date +%s.%N)"
DOCKER_SOCK="/var/run/docker.sock"
if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps --format "{{.ID}}" --filter "label=docker-volume-backup.stop-during-backup=$BACKUP_IDENT" > "$TEMPFILE"
  CONTAINERS_TO_STOP="$(cat $TEMPFILE | tr '\n' ' ')"
  CONTAINERS_TO_STOP_TOTAL="$(cat $TEMPFILE | wc -l)"
  CONTAINERS_TOTAL="$(docker ps --format "{{.ID}}" | wc -l)"
  rm "$TEMPFILE"
  echo "$CONTAINERS_TOTAL containers running on host in total"
  echo "$CONTAINERS_TO_STOP_TOTAL containers marked to be stopped during backup"
else
  CONTAINERS_TO_STOP_TOTAL="0"
  CONTAINERS_TOTAL="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop"
fi


if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps \
    --filter "label=docker-volume-backup.exec-pre-backup" \
    --format '{{.ID}} {{.Label "docker-volume-backup.exec-pre-backup"}}' \
    > "$TEMPFILE"
  while read line; do
    info "Pre-exec command: $line"
    docker exec $line
  done < "$TEMPFILE"
  rm "$TEMPFILE"
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Stopping containers"
  docker stop $CONTAINERS_TO_STOP
fi

info "Creating backup"
BACKUP_FILENAME=$(date +"$BACKUP_FILENAME_TEMPLATE")
TIME_BACK_UP="$(date +%s.%N)"
tar -czf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
BACKUP_SIZE="$(du --bytes $BACKUP_FILENAME | sed 's/\s.*$//')"
TIME_BACKED_UP="$(date +%s.%N)"

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Starting containers back up"
  docker start $CONTAINERS_TO_STOP
fi

if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps \
    --filter "label=docker-volume-backup.exec-post-backup" \
    --format '{{.ID}} {{.Label "docker-volume-backup.exec-post-backup"}}' \
    > "$TEMPFILE"
  while read line; do
    info "Post-exec command: $line"
    docker exec $line
  done < "$TEMPFILE"
  rm "$TEMPFILE"
fi

info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

TIME_UPLOAD="0"
TIME_UPLOADED="0"
if [ ! -z "$AWS_S3_BUCKET_NAME" ]; then
  info "Uploading backup to S3"
  echo "Will upload to bucket \"$AWS_S3_BUCKET_NAME\""
  TIME_UPLOAD="$(date +%s.%N)"
  aws $AWS_EXTRA_ARGS s3 cp --only-show-errors "$BACKUP_FILENAME" "s3://$AWS_S3_BUCKET_NAME/"
  echo "Upload finished"
  TIME_UPLOADED="$(date +%s.%N)"
fi

if [ -d "$BACKUP_ARCHIVE" ]; then
  info "Archiving backup"
  mv -v "$BACKUP_FILENAME" "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
fi

if [ -f "$BACKUP_FILENAME" ]; then
  info "Cleaning up"
  rm -vf "$BACKUP_FILENAME"
fi

info "Collecting metrics"
TIME_FINISH="$(date +%s.%N)"
INFLUX_LINE="$INFLUXDB_MEASUREMENT\
,host=$BACKUP_HOSTNAME\
\
 size_compressed_bytes=$BACKUP_SIZE\
,containers_total=$CONTAINERS_TOTAL\
,containers_stopped=$CONTAINERS_TO_STOP_TOTAL\
,time_wall=$(perl -E "say $TIME_FINISH - $TIME_START")\
,time_total=$(perl -E "say $TIME_FINISH - $TIME_START - $BACKUP_WAIT_SECONDS")\
,time_compress=$(perl -E "say $TIME_BACKED_UP - $TIME_BACK_UP")\
,time_upload=$(perl -E "say $TIME_UPLOADED - $TIME_UPLOAD")\
"
echo "$INFLUX_LINE" | sed 's/ /,/g' | tr , '\n'

if [ ! -z "$INFLUXDB_URL" ]; then
  info "Shipping metrics"
  curl \
    --silent \
    --include \
    --request POST \
    --user "$INFLUXDB_CREDENTIALS" \
    "$INFLUXDB_URL/write?db=$INFLUXDB_DB" \
    --data-binary "$INFLUX_LINE"
fi

info "Backup finished"
echo "Will wait for next scheduled backup"
