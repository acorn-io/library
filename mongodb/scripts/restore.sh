#!/bin/bash
BACKUP_DIR='/backups'
BACKUP_TO_RESTORE="${BACKUP_DIR}/${BACKUP_FILENAME}"
if [ ! -f "${BACKUP_TO_RESTORE}" ]; then
	echo "Backup file ${BACKUP_TO_RESTORE} not found!"
	exit 1
fi

echo "Locking backup volume to restore ${BACKUP_FILENAME}..."
touch ${BACKUP_DIR}/restore_in_progress

# comparison is performed without regard to the case of alphabetic characters
shopt -s nocasematch
OPLOG_FLAG=""
if [[ "$PTR_BACKUP" = 1 || "$PTR_BACKUP" =~ ^(yes|true)$ ]]; then
    OPLOG_FLAG="--oplogReplay"
fi

COLLECTION_OPTION=""
if [[ -z "$RESTORE_COLLECTION" ]]; then
    COLLECTION_OPTION="--collection=$RESTORE_COLLECTION"
fi

DATABASE_OPTION=""
if [[ -z "$RESTORE_DB" ]]; then
    DATABASE_OPTION="--db=$RESTORE_DB"
fi

echo "Restoring..."
mongorestore $OPLOG_FLAG $COLLECTION_OPTION $DATABASE_OPTION \
    -u $RESTORE_USER \
    -p $RESTORE_PASSWORD \
    --authenticationDatabase admin \
	--archive="$BACKUP_TO_RESTORE" \
	--gzip \
	--uri "$MONGODB_URI"

echo "Unlock backup volume."
rm ${BACKUP_DIR}/restore_in_progress
echo "Restore success!"