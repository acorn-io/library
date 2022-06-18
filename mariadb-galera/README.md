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
 1. Test scaling up/down.
 1. Add alias lb.
 1. Add docs to expose each node.

## Available options

```shell
Volumes:   mysql-data-0, mysql-data-1, mysql-data-2
Secrets:   db-user-credentials, backup-user-credentials, create-backup-user, client-config, mysqld-config, galera-config, root-credentials
Container: mariadb-0, mariadb-1, mariadb-2
Ports:     mariadb-0:3306/tcp, mariadb-1:3306/tcp, mariadb-2:3306/tcp

      --boot-strap-index int   Server to have boot strap a new cluster
      --cluster-name string    Galera cluster name
      --db-name string         Specify the name of the database to create
      --db-user-name string    Specify the username of db user
      --force-recover          When recovering the cluster this will force safe_to_bootstrap in grastate.dat for the bootStrapIndex node.
      --recovery               Put the cluster into recovery mode.
      --replicas int           Number of nodes to run in the galera cluster
```

## Advanced Usage

### Recover from shutdown/full quorem loss

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
