#!/bin/bash
. /acorn/scripts/common_libs.sh
. /acorn/scripts/mongo_libs.sh
. /acorn/scripts/env.sh

if is_empty_value "$MONGODB_ADVERTISED_PORT_NUMBER"; then
    export MONGODB_ADVERTISED_PORT_NUMBER="$MONGODB_PORT_NUMBER"
fi
shopt -s nocasematch

if [[ "$TLS_ENABLED" = 1 || "$TLS_ENABLED" =~ ^(yes|true)$ ]]; then
    export MONGODB_CLIENT_EXTRA_FLAGS="--tls --tlsCertificateKeyFile=/certs/mongodb.pem --tlsCAFile=/certs/mongodb-cert"
    export MONGODB_EXTRA_FLAGS="--tlsMode=$TLS_MODE --tlsCertificateKeyFile=/certs/mongodb.pem --tlsCAFile=/certs/mongodb-cert $MONGODB_EXTRA_FLAGS"
fi

info "Advertised Hostname: $MONGODB_ADVERTISED_HOSTNAME"
info "Advertised Port: $MONGODB_ADVERTISED_PORT_NUMBER"
# Check for existing replica set in case there is no data in the PVC
# This is for cases where the PVC is lost or for MongoDB caches without
# persistence
current_primary=""
if is_dir_empty "${MONGODB_DATA_DIR}/db"; then
    info "Data dir empty, checking if the replica set already exists"
    current_primary=$(mongosh admin $MONGODB_CLIENT_EXTRA_FLAGS --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'db.runCommand("ismaster")' | awk -F\' '/primary/ {print $2}')
    if ! is_empty_value "$current_primary"; then
        info "Detected existing primary: ${current_primary}"
    fi
fi


if ! is_empty_value "$current_primary" && [[ "$MONGODB_ADVERTISED_HOSTNAME:$MONGODB_ADVERTISED_PORT_NUMBER" == "$current_primary" ]]; then
    info "Advertised name matches current primary, configuring node as a primary"
    export MONGODB_REPLICA_SET_MODE="primary"
elif ! is_empty_value "$current_primary" && [[ "$MONGODB_ADVERTISED_HOSTNAME:$MONGODB_ADVERTISED_PORT_NUMBER" != "$current_primary" ]]; then
    info "Current primary is different from this node. Configuring the node as replica of ${current_primary}"
    export MONGODB_REPLICA_SET_MODE="secondary"
    export MONGODB_INITIAL_PRIMARY_HOST="${current_primary%:*}"
    export MONGODB_INITIAL_PRIMARY_PORT_NUMBER="${current_primary#*:}"
    export MONGODB_SET_SECONDARY_OK="yes"
elif [[ "$MY_POD_INDEX" = "0" ]]; then
    info "Pod name matches initial primary pod name, configuring node as a primary"
    export MONGODB_REPLICA_SET_MODE="primary"
else
    info "Pod name doesn't match initial primary pod name, configuring node as a secondary"
    export MONGODB_REPLICA_SET_MODE="secondary"
    export MONGODB_INITIAL_PRIMARY_PORT_NUMBER="$MONGODB_PORT_NUMBER"
fi
if [[ "$MONGODB_REPLICA_SET_MODE" == "secondary" ]]; then
    export MONGODB_INITIAL_PRIMARY_ROOT_USER="$MONGODB_ROOT_USER"
    export MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD="$MONGODB_ROOT_PASSWORD"
    export MONGODB_ROOT_PASSWORD=""
    export MONGODB_USERNAME=""
    export MONGODB_EXTRA_USERNAMES=""
    export MONGODB_EXTRA_DATABASES=""
    export MONGODB_EXTRA_PASSWORDS=""
    export MONGODB_ROOT_PASSWORD_FILE=""
    export MONGODB_EXTRA_USERNAMES_FILE=""
    export MONGODB_EXTRA_DATABASES_FILE=""
    export MONGODB_EXTRA_PASSWORDS_FILE=""
fi
/acorn/scripts/run.sh