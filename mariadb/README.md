# Mariadb Galera Cluster

---

This Acorn provides a multi-node galera cluster.

## Pre-req

* storage class for PVs

## Quick start

`acorn run [MARIADB_GALERA_IMAGE]`

This will create a three node cluster with a default database acorn.

You can get the username and root password if needed from the generated secrets.

## Production considerations

By default this will start a single instance of MariaDB with 1 replica on a 10GB volume from the default storage class. In a production setting you will want to customize this, along with the size and storage class of the backup volumes.

#### TODOs

Document how to mount volumes and custom types.

* Add a way to reset root password
* Add a way to pass in custom backup scripts
* Add clean up of older backups.. also limit the number kept.

## Available options

```shell
Volumes:   mysql-backup-vol, mysql-data-0
Secrets:   root-credentials, db-user-credentials, backup-user-credentials, create-backup-user, mariadb-0-client-config, mariadb-0-mysqld-config, mariadb-0-galera-config
Container: mariadb-0
Ports:     mariadb-0:3306/tcp

      --backup-schedule string         Backup Schedule
      --boot-strap-index int           Galera: set server to boot strap a new cluster. Default(0)
      --cluster-name string            Galera: cluster name
      --custom-mariadb-config string   User provided MariaDB config
      --db-name string                 Specify the name of the database to create. Default(acorn)
      --db-user-name string            Specify the username of db user
      --force-recover                  Galera: When recovering the cluster this will force safe_to_bootstrap in grastate.dat for the bootStrapIndex node.
      --recovery                       Galera: run cluster into recovery mode.
      --replicas int                   Number of nodes to run in the galera cluster. Default (1)
```

## Basics

### Accessing mariadb

By default the Acorn creates a single replica which can be accessed via the `mariadb-0` service.

If you are going to run in an active-active state with multiple r/w replicas you will want to expose the `mariadb` service and access that through a load balancer.

### Adding replicas

By default the MariaDB chart starts a single r/w replica. In production settings you would typically want more then one replica running. Users have two options with this chart. One method is to add additional passive followers to the primary server. When one of these passive replicas fail or experience an outage nothing happens to the running primary server. If the primary r/w replica fails then service will be down until it is restored.

Alternatively, the Acorn can configure the replicas to run in an active-active state with multiple replicas able to perform r/w operations.

#### Active-Passive replication

If you would like to run active-passive then you will need to create a custom yaml file like so:

config.yaml

```yaml
---
replicas:
  "mariadb-1":
    galera:
      wsrep_provider_options: "pc.weight=0"
  ...
```

Then update your deployment:
`acorn update [APP-NAME] --custom-mariadb-config @config.yaml --replicas 2`

This will startup a second replica that can be used for backups, and read-only access.

#### Active-Active replication

Galera clusters have a quorem algorithm to prevent split brain scenarios. Ideally clusters run with an odd number of replicas.

By default there are three replicas running and there shouldn't be less. This allows for 1 replica to fail and still serve data. Additional replicas can be added by updating the application to the total number of replicas desired in the end state.

`acorn update [APP-NAME] --replicas 5`

This will create an additional 2 replicas in the cluster to equal 5.

### Removing replicas

Removing replicas should be done 1 at a time until the desired state is reached. The highest replica indexes will be removed first. If you have 5 replicas running, you can scale down to 3 by updating the app with 1 less then the total running.

`acorn update [APP-NAME] --replicas 4`

Before moving on, you should verify the cluster is in a good state. Shell into the `0` index replica to check that the cluster is the correct size, and there is still a "Primary" partition.

```shell
acorn exec -c mariadb-0 [APP-NAME]

mysql -uroot -p${MARIADB_ROOT_PASSWORD}

MariaDB [(none)]> show status like '%wsrep_cluster_size%';
+--------------------+-------+
| Variable_name      | Value |
+--------------------+-------+
| wsrep_cluster_size | 4     |
+--------------------+-------+
1 row in set (0.001 sec)

MariaDB [(none)]> show status like '%wsrep_cluster_status';
+----------------------+---------+
| Variable_name        | Value   |
+----------------------+---------+
| wsrep_cluster_status | Primary |
+----------------------+---------+
1 row in set (0.002 sec)
```

If these are the values you see, you can then remove the next replica. If the cluster size is not what you expect, check the logs of all pods to determine if there is an issue. If cluster status is no longer Primary, check on all replicas to see if there is a split brain. Follow the quorem loss procedure below to restore quorem.

`acorn update [APP-NAME] --replicas 3`

Exec into the `mariadb-0` replica as above to check the cluster size is now 3 and still "Primary".

Once the desired number of replicas is achieved and the cluster is in a good state, you can also clean up the volumes from the non-existant replicas.

```shell
> acorn volumes
NAME                                       APP-NAME   BOUND-VOLUME   CAPACITY   STATUS     ACCESS-MODES   CREATED
pvc-f457051e-19a4-4d85-8ca0-046b60df060b   dry-sea    mysql-data-4   10G        released   RWO            24m ago
pvc-2b221e93-5476-4368-9622-53cebbbaf2ae   dry-sea    mysql-data-2   10G        bound      RWO            24m ago
pvc-c8a768f7-7328-48d9-ba23-7bf6d7af7148   dry-sea    mysql-data-1   10G        bound      RWO            24m ago
pvc-d5b3bad7-f1de-4eba-ab0d-d671bf4ff84e   dry-sea    mysql-data-3   10G        released   RWO            24m ago
pvc-88f43b37-f201-4478-8e6f-0ed875f2c791   dry-sea    mysql-data-0   10G        bound      RWO            84m ago

> acorn rm -v pvc-f457051e-19a4-4d85-8ca0-046b60df060b pvc-d5b3bad7-f1de-4eba-ab0d-d671bf4ff84e
pvc-f457051e-19a4-4d85-8ca0-046b60df060b
pvc-d5b3bad7-f1de-4eba-ab0d-d671bf4ff84e
```

### Backups

#### Enabling Backups

If you would like to back up your database, you can launch with or update the app with a `--backup-schedule`. The backup schedule is in cron format.

Here is an example of how you could do daily backups:
`acorn run [MARIADB_ACORN_IMAGE] --backup-schedule "0 0 * * *"`

If you would like to add backups to an already running cluster, you can do:
`acorn update [APP-NAME] --backup-schedule "0 0 * * *"`

Backups are run from pod that will mount both the data volume from the `mariadb-0` replica and a separate backup volume. The job uses `mariabackup` to perform the backup of the database cluster.

#### Listing available backups

To see which backups are available, you can list them by exposing the content of the backup-list secret. First, find the secret name:

```shell
> acorn secrets
NAME                            TYPE                        KEYS                  CREATED
backup-list-d5bxh               Opaque                      [content]             19h ago
backup-user-credentials-vlgk9   kubernetes.io/basic-auth    [password username]   20h ago
create-backup-user-6zjkk        secrets.acorn.io/template   [template]            20h ago
db-user-credentials-jcmpb       kubernetes.io/basic-auth    [password username]   20h ago
mariadb-0-client-config-zsj27   secrets.acorn.io/template   [template]            20h ago
mariadb-0-galera-config-vv64p   secrets.acorn.io/template   [template]            20h ago
mariadb-0-mysqld-config-vb5nk   secrets.acorn.io/template   [template]            20h ago
root-credentials-v55zt          kubernetes.io/basic-auth    [password username]   20h ago
```

Once you have the full name of the backup secret, list the contents:

```shell
> acorn secret expose backup-list-d5bxh
-rw-r--r-- 1 root root 5296236 Jun 23 18:48 galera-mariadb-backup-20220623-184802.tgz
...
-rw-r--r-- 1 root root 5301593 Jun 23 20:20 galera-mariadb-backup-20220623-202002.tgz
```

#### Restoring from backup

Only follow this procedure if you are certain you need to restore data. This procedure will cause ALL data to be LOST since the time of the backup.

To restore from backup, first identify which backup you want to restore from in the list above.

Update the app:
`acorn update [APP-NAME] --restore-from-backup [BACKUP FILE NAME] --replicas 0`

This will scale down the servers, and initiate a `restore-from-backup` job.

## Advanced Usage

### Custom configuration

You can pass in configuration in the form of YAML or Cue. For simple overrides, YAML can be passed in with the following structure.

```yaml
config_block:
  key: "value"
```

So to pass or update a setting in the `mysqld` configuration block create a config.yaml with the content:

```yaml
mysqld:
  max_connections: 1024
```

You can set per-replica configurations if needed by placing the configurations under the `replica` top level key. Each node, specified in `mariadb-\(i)` where `i` is the replica number, can have custom configuration per config block.

```yaml
mysqld:
  max_connections: 1024
replicas:
  mariadb-0:
    mysqld:
     max_connections: 512
```

Then run/update the app like so:

`acorn run [MARIADB_GALERA_IMAGE] --custom-mariadb-confg @config.yaml`

This will get merged with the configuration defined in the Acorn. the defaul config block can be found [here](https://github.com/acorn-io/acorn-library/blob/main/mariadb-galera/acorn.cue#L207).

Some of the configuration values can not be changed.

### Active - Passive recovery from primary shutdown/failure

#### No data loss

If the primary replica `mariadb-0` shutdown unexpectedly and the data is still present on the volume you can follow this procedure.

`acorn update [APP-NAME] --recovery --force-bootstrap`

Once you see in the logs that the server has come up once, you can move on to step 2. The node won't be ready to run yet until the next step.

`acorn update [APP-NAME] --recovery=false --force-bootstrap=false`

The clusters will come up as expected after this.

### Active - Active recovery from shutdown/quorem loss

When a cluster is completely shutdown, or has lost a majority of the nodes you need to follow a series of manual steps to recover.

1.) Update the deployment with the `acorn update [APP-NAME] --recovery` flag.

2.) When the services have come up run `acorn logs little-darkness | grep WSREP`

```shell
mariadb-galera % acorn logs [APP-NAME] | grep WSREP
mariadb-0-746754d68d-mgwpz/mariadb-0: 2022-06-17 23:57:15 0 [Note] WSREP: Recovered position: 8d5f1139-ee97-11ec-b8ef-7359029eaa77:2
mariadb-1-7d977b8fb8-f8lwx/mariadb-1: 2022-06-17 23:57:17 0 [Note] WSREP: Recovered position: 8d5f1139-ee97-11ec-b8ef-7359029eaa77:3
mariadb-2-7f49689648-6h7kf/mariadb-2: 2022-06-17 23:57:18 0 [Note] WSREP: Recovered position: 8d5f1139-ee97-11ec-b8ef-7359029eaa77:3
```

3.) Find the node with the highest position value. In this case we can use `mariadb-1` or `mariadb-2` since they are both at 3.

4.) Update the app so that `acorn update [APP-NAME] --recovery --force-recover --boot-strap-index 2`. We are using `2` because it is the most advanced. If the containers have come up and you do not see "failed to update grastate.data" then the app is ready to update.

5.) `acorn update [APP-NAME] --recovery=false --force-recover=false`. This will cause the containers to restart and the new boot-strap-index node will start the cluster.
