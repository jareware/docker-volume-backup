#!/bin/bash

# Cronjobs don't inherit their env, so load from file
source env.sh

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

if [ "$CHECK_HOST" != "false" ]; then
  info "Check host availability"
  TEMPFILE="$(mktemp)"
  ping -c 1 $CHECK_HOST | grep '1 packets transmitted, 1 received' > "$TEMPFILE"
  PING_RESULT="$(cat $TEMPFILE)"
  if [ ! -z "$PING_RESULT" ]; then
    echo "$CHECK_HOST is available."
  else
    echo "$CHECK_HOST is not available."
    info "Backup skipped"
    exit 0
  fi
fi

info "Backup starting"
TIME_START="$(date +%s.%N)"
DOCKER_SOCK="/var/run/docker.sock"

if [ ! -z "$BACKUP_CUSTOM_LABEL" ]; then
  CUSTOM_LABEL="--filter label=$BACKUP_CUSTOM_LABEL"
fi

if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps --format "{{.ID}}" --filter "label=docker-volume-backup.stop-during-backup=true" $CUSTOM_LABEL > "$TEMPFILE"
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

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Stopping containers"
  docker stop $CONTAINERS_TO_STOP
fi

if [ -S "$DOCKER_SOCK" ]; then
  for id in $(docker ps --filter label=docker-volume-backup.exec-pre-backup $CUSTOM_LABEL --format '{{.ID}}'); do
    name="$(docker ps --filter id=$id --format '{{.Names}}')"
    cmd="$(docker ps --filter id=$id --format '{{.Label "docker-volume-backup.exec-pre-backup"}}')"
    info "Pre-exec command for: $name"
    echo docker exec $id $cmd # echo the command we're using, for debuggability
    eval docker exec $id $cmd
  done
fi

if [ ! -z "$PRE_BACKUP_COMMAND" ]; then
  info "Pre-backup command"
  echo "$PRE_BACKUP_COMMAND"
  eval $PRE_BACKUP_COMMAND
fi

info "Creating backup"
BACKUP_FILENAME="$(date +"${BACKUP_FILENAME:-backup-%Y-%m-%dT%H-%M-%S.tar.gz}")"
TIME_BACK_UP="$(date +%s.%N)"
tar -czvf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
BACKUP_SIZE="$(du --bytes $BACKUP_FILENAME | sed 's/\s.*$//')"
TIME_BACKED_UP="$(date +%s.%N)"

if [ ! -z "$GPG_PASSPHRASE" ]; then
  info "Encrypting backup"
  gpg --symmetric --cipher-algo aes256 --batch --passphrase "$GPG_PASSPHRASE" -o "${BACKUP_FILENAME}.gpg" $BACKUP_FILENAME
  rm $BACKUP_FILENAME
  BACKUP_FILENAME="${BACKUP_FILENAME}.gpg"
fi

if [ -S "$DOCKER_SOCK" ]; then
  for id in $(docker ps --filter label=docker-volume-backup.exec-post-backup $CUSTOM_LABEL --format '{{.ID}}'); do
    name="$(docker ps --filter id=$id --format '{{.Names}}')"
    cmd="$(docker ps --filter id=$id --format '{{.Label "docker-volume-backup.exec-post-backup"}}')"
    info "Post-exec command for: $name"
    echo docker exec $id $cmd # echo the command we're using, for debuggability
    eval docker exec $id $cmd
  done
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Starting containers back up"
  docker start $CONTAINERS_TO_STOP
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
if [ ! -z "$AWS_GLACIER_VAULT_NAME" ]; then
  info "Uploading backup to GLACIER"
  echo "Will upload to vault \"$AWS_GLACIER_VAULT_NAME\""
  TIME_UPLOAD="$(date +%s.%N)"
  aws $AWS_EXTRA_ARGS glacier upload-archive --account-id - --vault-name "$AWS_GLACIER_VAULT_NAME" --body "$BACKUP_FILENAME"
  echo "Upload finished"
  TIME_UPLOADED="$(date +%s.%N)"
fi

if [ ! -z "$SCP_HOST" ]; then
  SSH_CONFIG="-o StrictHostKeyChecking=no -i /ssh/id_rsa"
  if [ ! -z "$PRE_SCP_COMMAND" ]; then
    info "Pre-scp command"
    echo "$PRE_SCP_COMMAND"
    eval ssh -p $SCP_PORT $SSH_CONFIG $SCP_USER@$SCP_HOST $PRE_SCP_COMMAND
  fi
  info "Uploading backup by means of SCP"
  echo "Will upload to $SCP_HOST:$SCP_DIRECTORY"
  TIME_UPLOAD="$(date +%s.%N)"
  scp  -P $SCP_PORT $SSH_CONFIG $BACKUP_FILENAME $SCP_USER@$SCP_HOST:$SCP_DIRECTORY
  echo "Upload finished"
  TIME_UPLOADED="$(date +%s.%N)"
  if [ ! -z "$POST_SCP_COMMAND" ]; then
    info "Post-scp command"
    echo "$POST_SCP_COMMAND"
    eval ssh -p $SCP_PORT $SSH_CONFIG $SCP_USER@$SCP_HOST $POST_SCP_COMMAND
  fi
fi

if [ -d "$BACKUP_ARCHIVE" ]; then
  info "Archiving backup"
  mv -v "$BACKUP_FILENAME" "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
  if (($BACKUP_UID > 0)); then
    chown -v $BACKUP_UID:$BACKUP_GID "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
  fi
fi

if [ ! -z "$POST_BACKUP_COMMAND" ]; then
  info "Post-backup command"
  echo "$POST_BACKUP_COMMAND"
  eval $POST_BACKUP_COMMAND
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

if [ ! -z "$INFLUXDB_CREDENTIALS" ]; then
  info "Shipping metrics"
  curl \
    --silent \
    --include \
    --request POST \
    --user "$INFLUXDB_CREDENTIALS" \
    "$INFLUXDB_URL/write?db=$INFLUXDB_DB" \
    --data-binary "$INFLUX_LINE"
elif [ ! -z "$INFLUXDB_API_TOKEN" ]; then
  info "Shipping metrics"
  curl \
    --silent \
    --include \
    --request POST \
    --header "Authorization: Token $INFLUXDB_API_TOKEN" \
    "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORGANIZATION&bucket=$INFLUXDB_BUCKET" \
    --data-binary "$INFLUX_LINE"
fi

info "Backup finished"
echo "Will wait for next scheduled backup"
