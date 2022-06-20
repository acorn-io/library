# Mariadb Galera Cluster

---

This Acorn provides a multi-node galera cluster.

## Pre-req

* storage class for PVs

## Quick start

`acorn run [MARIADB_GALERA_IMAGE]`

This will create a three node cluster with a default database acorn.

You can get the username and root password if needed from the generated secrets.

## To Dos

 1. Add backups / restore.

## Available options

```shell
Volumes:   mysql-data-0, mysql-data-1, mysql-data-2
Secrets:   root-credentials, db-user-credentials, backup-user-credentials, create-backup-user, client-config, mysqld-config, galera-config
Container: mariadb-0, mariadb-1, mariadb-2
Ports:     mariadb-0:3306/tcp, mariadb-1:3306/tcp, mariadb-2:3306/tcp

      --boot-strap-index int           Galera: set server to boot strap a new cluster
      --cluster-name string            Galera: cluster name
      --custom-mariadb-config string   User provided MariaDB config
      --db-name string                 Specify the name of the database to create
      --db-user-name string            Specify the username of db user
      --expose string                  Expose nodes 'direct' or via 'lb'(default)
      --force-recover                  Galera: When recovering the cluster this will force safe_to_bootstrap in grastate.dat for the bootStrapIndex node.
      --recovery                       Galera: run cluster into recovery mode.
      --replicas int                   Number of nodes to run in the galera cluster. Default (3)
```

## Basics

### Accessing the cluster

By default the Acorn exposes the cluster via the mariadb alias. When the Acorn comes up there will be an internal service mariadb that your applications can access. If that service is exposed, it will front all replicas with a load balancer.

There is also a `direct` mode. When launched with this setting each node will be exposed individually by it's name-index, like `mariadb-0, mariadb-1, etc...`.

### Adding replicas

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

## Advanced Usage

### Single node MariaDB node

You can launch a stand alone non-galera cluster by running:
`acorn run [MARIADB_GALERA_IMAGE] --replicas 1`

This will create a single node instalation of the database server.

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

Then run/update the app like so:

`acorn run [MARIADB_GALERA_IMAGE] --custom-mariadb-confg @config.yaml`

This will get merged with the configuration defined in the Acorn. the defaul config block can be found [here](https://github.com/acorn-io/acorn-library/blob/main/mariadb-galera/acorn.cue#L207).

Some of the configuration values can not be changed.

## Galera

### Recover from shutdown/quorem loss

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
