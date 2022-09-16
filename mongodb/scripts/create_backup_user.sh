#!/bin/bash
# TODO(joseb): Consider pre-existing user
shopt -s nocasematch
AUTH_FLAG="--authenticationDatabase admin -u $MONGODB_ROOT_USER -p $MONGODB_ROOT_PASSWORD"
if [[ "$ALLOW_EMPTY_PASSWORD" = 1 || "$ALLOW_EMPTY_PASSWORD" =~ ^(yes|true)$ ]]; then
    AUTH_FLAG=""
fi

mongosh admin $AUTH_FLAG \
--host $MONGODB_SERVER_LIST \
--eval 'db.createUser( { user: "'$BACKUP_USER'", pwd: "'$BACKUP_PASSWORD'", roles: [{ role: "backup", db: "admin" }] })'
