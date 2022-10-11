#!/bin/bash
shopt -s nocasematch
AUTH_FLAG="--authenticationDatabase admin -u $MONGODB_ROOT_USER -p $MONGODB_ROOT_PASSWORD"
if [[ "$ALLOW_EMPTY_PASSWORD" = 1 || "$ALLOW_EMPTY_PASSWORD" =~ ^(yes|true)$ ]]; then
    AUTH_FLAG=""
fi

if [[ "$TLS_ENABLED" = 1 || "$TLS_ENABLED" =~ ^(yes|true)$ ]]; then
    TLS_OPTIONS='--tls --tlsCertificateKeyFile=/certs/mongodb.pem --tlsCAFile=/certs/mongodb-cert'
fi

mongosh admin $TLS_OPTIONS $AUTH_FLAG \
--host $MONGODB_SERVER_LIST \
--eval 'if (db.getUser("'$RESTORE_USER'") == null) {  db.createUser( { user: "'$RESTORE_USER'", pwd: "'$RESTORE_PASSWORD'", roles: [{ role: "restore", db: "admin" }] }) }'
