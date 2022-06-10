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
Volumes:   acorn-follower-data-0, redis-data-dir-0, redis-follower-data-0, acorn-data-0
Secrets:   redis-auth, redis-leader-config, redis-user-data, redis-follower-config
Container: redis-0, redis-follower-0
Ports:     redis-0:6379/tcp, redis-follower-0:6379/tcp

      --redis-follower-config string   User provided configuration for leader and cluster servers
      --redis-leader-config string     User provided configuration for leader and cluster servers
      --redis-leader-count int         Redis leader replica count. Setting this value 3 and above will configure Redis cluster.
      --redis-password string          Sets the requirepass value otherwise one is randomly generated
      --redis-replica-count int        Redis replicas per leader. To run in stand alone set to 0
```

## Advanced Usage

### Stand alone/Dev mode

You can run in stand alone mode with only a single read-write instance by setting the `--redis-replica-count` to `0`.

### Custom configuration

Custom configuration can be provided for leaders and follower node types. The passed in configuration will be merged with the Acorn values. The configuration data can be passed in via `yaml` or `cue` file. It should be in the form of `key: value` pairs.

For example redis-test.yaml

```yaml
timeout: 60
tcp-keepalive: 300
save: "1800 1 150 50 60 10000"
```

Can be passed like:
`acorn run <IMAGE> --redis-leader-config @redis-test.yaml --redis-replica-count 0`

This will merge with the predefined redis config. There are some values that can not be overriden:

#### All Server Roles

```shell
requirepass
port
dir
```

#### Follower Roles

```shell
masterauth
slaveof
slave-read-only
```

#### Leader / Cluster Roles

```shell
cluster-enabled
cluster-config-file
appendonly
```

### Adding additional replicas

When running in leader/follower mode you can add additional read-only replicas if needed. Update the app with `--redis-replica-count <total>`

### Running in cluster mode

To run in cluster mode, you will need to determine how many primary and how many replicas you would like to run. You will need a minimum of 3 leader nodes to setup the cluster. Then you can specify how many replicas to back up each leader. A simple cluster with redundancy can be deployed as follows:

`acorn run <REDIS_IMAGE> --redis-leader-count 3 --redis-replica-count 1`

This will create a cluster with three nodes each backed up by a single replica. This will deploy 6 containers in total. Every time you scale up a leader you will also scale up a replica.

#### Adding additional nodes

To add additional nodes, simply change the scale of the `--redis-leader-count` to a higher number.
`acorn update --image [REDIS] [APP_NAME] --redis-leader-count 4 --redis-replica-count 1`

This will add an additional leader and replica (assuming there were 3 leaders previously). These new pods will be added to the cluster one as a leader and the other a replica of that new leader. The cluster will automatically be rebalanced once the new leader has been added.

#### Removing nodes

Before removing nodes from the redis cluster you must first empty them. Nodes will be removed in descending order. Nodes are named redis-[LEADER]-[FOLLOWER] so the highest leader and all followers will be removed on the scale down operation. **Note** During normal redis cluster operations leaders and followers might switch roles. This process requires manual intervention to detach the replicas and empty any leaders. Once this is done, you can scale down the cluster.

Follow REDIS docs: <https://redis.io/docs/manual/scaling/#removing-a-node> to learn how to empty, reshard and remove nodes.
