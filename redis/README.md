# Redis Acorn

---
This Acorn deploys Redis in a single leader with multiple followers or in Redis Cluster configuration.

## Quick start

To quickly deploy a replicated Redis setup simply run the acorn:

`acorn run <REDIS_IMG>`

This will create a single Redis server and a single read only replica.

Auth will be setup, and you can obtain the password under the token via:
`acorn secret expose redis-auth-<uid>`

If you set the value in the env var REDISCLI_AUTH the `redis-cli` will automatically pick it up.
`export REDISCLI_AUTH=<value>`

You can connect to the Redis instance via the `redis-cli -h <lb-ip>` if the env var above is set you will automatically be logged in, otherwise you need to `AUTH <secret value>`

### Available options

```shell
Volumes:   redis-leader-data-dir-0, redis-follower-data-0
Secrets:   redis-auth, redis-leader-config, redis-follower-config
Container: redis-0, redis-follower-0
Ports:     redis-0:6379/tcp

      --redis-leader-count int    Redis leader replica count. Setting this value above 1 will configure Redis cluster.
      --redis-password string     Sets the requirepass value otherwise one is randomly generated
      --redis-replica-count int   Redis replicas per leader. To run in stand alone set to 0
```

## Advanced Usage

### Stand alone/Dev mode

You can run in stand alone mode with only a single read-write instance by setting the `--redis-replica-count` to 0.

### Adding additional replicas

When running in leader/follower mode you can add additional read-only replicas if needed. Update the app with `--redis-replica-count <total>`

### Running in cluster mode

To run in cluster mode, you will need to determine how many primary and how many replicas you would like to run. You will need a minimum of 3 leader nodes to setup the cluster. Then you can specify how many replicas to back up each leader. A simple cluster with redundancy can be deployed as follows:

`acorn run <REDIS_IMAGE> --redis-leader-count 3 --redis-replica-count 1`

This will create a cluster with three nodes each backed up by a single replica. This will deploy 6 containers in total.
