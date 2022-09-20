#!/bin/bash
. /opt/bitnami/scripts/mongodb-env.sh
echo "Advertised Hostname: $MONGODB_ADVERTISED_HOSTNAME"
echo "Advertised Port: $MONGODB_ADVERTISED_PORT_NUMBER"
echo "Configuring node as a hidden node"

if [[ "$TLS_ENABLED" = 1 || "$TLS_ENABLED" =~ ^(yes|true)$ ]]; then
    export MONGODB_CLIENT_EXTRA_FLAGS="--tls --tlsCertificateKeyFile=/certs/mongodb.pem --tlsCAFile=/certs/mongodb-cert"
    export MONGODB_EXTRA_FLAGS="--tlsMode=$TLS_MODE --tlsCertificateKeyFile=/certs/mongodb.pem --tlsCAFile=/certs/mongodb-cert $MONGODB_EXTRA_FLAGS"
fi

export MONGODB_REPLICA_SET_MODE="hidden"
export MONGODB_INITIAL_PRIMARY_ROOT_USER="$MONGODB_ROOT_USER"
export MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD="$MONGODB_ROOT_PASSWORD"
export MONGODB_INITIAL_PRIMARY_PORT_NUMBER="$MONGODB_PORT_NUMBER"
export MONGODB_ROOT_PASSWORD=""
export MONGODB_USERNAME=""
export MONGODB_EXTRA_USERNAMES=""
export MONGODB_EXTRA_DATABASES=""
export MONGODB_EXTRA_PASSWORDS=""
export MONGODB_ROOT_PASSWORD_FILE=""
export MONGODB_EXTRA_USERNAMES_FILE=""
export MONGODB_EXTRA_DATABASES_FILE=""
export MONGODB_EXTRA_PASSWORDS_FILE=""
exec /opt/bitnami/scripts/mongodb/entrypoint.sh /opt/bitnami/scripts/mongodb/run.sh