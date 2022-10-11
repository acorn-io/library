
#!/bin/bash

if [[ "$TLS_ENABLED" = 1 || "$TLS_ENABLED" =~ ^(yes|true)$ ]]; then
    TLS_OPTIONS='--tls --tlsCertificateKeyFile=/certs/mongodb.pem --tlsCAFile=/certs/mongodb-cert'
fi

mongosh $TLS_OPTIONS --port 27017 --eval "db.adminCommand('ping')"