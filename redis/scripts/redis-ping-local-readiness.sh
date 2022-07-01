#!/bin/sh
res=$(timeout -s 3 ${1} /usr/local/bin/redis-cli -h localhost -p 6379 ping)
if ["$?" -eq "124"]; then 
    echo "Timed out"
exit 1
fi
if ["$response" != "PONG"]; then
    echo "${response}"
    exit 1
fi
