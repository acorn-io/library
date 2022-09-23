# MongoDB Acorn

---

This Acorn provides MongoDB instance. Users can select the instance architecture.

## Quick start

`acorn run [--name ACORN_APP_NAME] [--target-namespace NAMESPACE] [MONGODB_IMAGE]`

This will create a standalone MongoDB instance.
In this instance, an initial user with `readWrite` role on an initial database `acorn` is created. MongoDB is fundamentally designed for "create on first use", so if you do not insert data, then no database is created.

You can get the username and password of that initial user if needed from the generated secrets.
`acorn secret expose ACORN_APP_NAME.db-user-credentials`
You can get the username and password of root user if needed from the generated secrets.
`acorn secret expose ACORN_APP_NAME.root-credentials`

## Production considerations

By default, this will start a standalone MongoDB instance on a 10GB volume from the default storage class. Do not use this deployment for production systems as it lacks replication and high availability. For all production deployments use replica sets.
You can simply use `prod` profile.
`acorn run --profile prod [MONGODB_IMAGE]`
This will deploy a replica set with 3 secondary nodes. In addition, it enables scheduled backup every 30 minutes.
To learn more about replica sets deployment, see [Deploy a Replica Set](#deploy-a-replica-set).

## Available options

```shell
  --is-replicaSet bool           Enable replicaset architecture. Default (false)
  --db-user-name string          Specify the username of db user.
  --db-name string               Specify the name of the database to create. Default(acorn)
  --replicas int                 Number of nodes to run in the MongoDB replica set. Default (3). Max (50)
  --diagnostic-mode bool         Enable diagnostic mode in the deployment. All probes will be disabled. Default (false)
  --auth-enabled bool            Enabling access control on a MongoDB deployment enforces authentication. Default (true)
  --extra-flags string           Additional command line flags of MongoDB instance. Default ("")
  --arbiter-enabled bool         Enable deploying the arbiter. Default (false)
  --arbiter-extra-flags string   Arbiter additional command line flags. Default ("")
  --hidden-replicas int          Number of hidden nodes. Only valid when isReplicaset=true. Default (1)
  --hidden-extra-flags string   Hidden node additional command line flags. Default ("")
  --backup-schedule string       Backup Schedule. Cron time string format. Default ("")
  --ptr-backup bool              Enable oplog backup for taking a point-in-time snapshot. Default (false)
  --backup-db string             Specify db name to backup. If not specified, backup all databases. Default ("")
  --backup-collection string     Specify collection name to backup. If not specified, backup all collections. Default ("")
  --backup-to-restore string     Specify backup name to restore. Default ("")
  --backup-retain-days int       Specify the number of days to keep backup files. Default (5)
```

## Basics

### Accessing MongoDB

By default, the Acorn creates a standalone instance that can be accessed via the `mongodb-0` service.
If you enabled replica set mode, that instance can be accessed via `mongodb-0,...mongodb-n`(`n` is the number of secondary nodes).

### Deploy a Replica Set

If you would like to deploy a replica set instance, you have to set `--is-replicaset` as true.
`acorn run [MONGODB_ACORN_IMAGE] --is-replicaset true`
This will deploy a replica set with 3 secondary nodes.

If you would like to deploy a replica set instance with more/fewer replicas and hidden nodes, you can specify replica numbers explicitly.
`acorn run [MONGODB_ACORN_IMAGE] --is-replicaset true --replicas 5 --hidden-replicas 2`
This will deploy 2 hidden nodes and 5 secondary nodes.

### How to check replica set status

```shell
acorn exec -c mongodb-0 [APP-NAME]

mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'rs.status()'
```

### Add members to an existing replica set

Replica sets cannot process write operations until the election is completed successfully, and an election can be triggered in response to adding a new node to the replica set. So you should
- check replica status before scaling
- add one replica at a time.


#### Adding replicas to a replica set with 7 voting members

A replica set can have a maximum of seven voting members. To add a member to a replica set that already has seven voting members, you must either add the member as a non-voting member or remove a vote from an existing member.

The following procedure configures a single secondary replica set member to be non-voting.

1) Connect to the Replica Set Primary
```shell
acorn exec -c mongodb-0 [APP-NAME]

mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD
```
2) Retrieve the Replica Configuration
```shell
cfg = rs.conf();
```
3) Configure the Member to be Non-Voting
For the replica member to change to be non-voting, set its votes and priority to 0. Replace n with the array index position of the member to modify.
```shell
cfg.members[n].votes = 0;

cfg.members[n].priority = 0;
```
4) Reconfigure the Replica Set with the New Configuration
```shell
rs.reconfig(cfg);
```
After `rs.reconfig()` can force the current primary to step down, which causes an election. So try to make this during scheduled maintenance periods.


Once non-voting is finshed and the replica set is in a good state, you can update the acorn app with n+1 replicas.
```shell
acorn update [APP-NAME] --replicas 8
```

#### Adding hidden nodes to a replicaset

If a replica set has an even number of members then you can add an arbiter.
```shell
acorn update [APP-NAME] --hiddenReplicas 2
```

#### Adding arbiter node to a replicaset

```shell
acorn update [APP-NAME] --arbiter-enabled true
```

### Removing replicas from an existing replica set

Removing replicas should be done 1 at a time until the desired state is reached. The highest replica indexes will be removed first. If you have 5 replicas running, you can scale down to 3 by updating the app with 1 less than the total running.

```shell
acorn update [APP-NAME] --replicas 4
mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'rs.remove("mongodb-5:27017")'
```
Before moving on, you should [verify](#how-to-check-replica-set-status) that the replica set is in a good state. If the replica set status is ok, scale down again to 3. If the replica set status is not what you expect, check the logs of all pods to determine if there is an issue.

```shell
acorn update [APP-NAME] --replicas 3
mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'rs.remove("mongodb-4:27017")'
```

Once the desired number of replicas is achieved and the replica set is in a good state, you can also clean up the volumes from the non-existent replicas.

```shell
> acorn volumes
NAME                                       APP-NAME   BOUND-VOLUME   CAPACITY   STATUS     ACCESS-MODES   CREATED
pvc-f457051e-19a4-4d85-8ca0-046b60df060b   mongo    mongodb-data-4   10G        released   RWO            24m ago
pvc-2b221e93-5476-4368-9622-53cebbbaf2ae   mongo    mongodb-data-2   10G        bound      RWO            24m ago
pvc-c8a768f7-7328-48d9-ba23-7bf6d7af7148   mongo    mongodb-data-1   10G        bound      RWO            24m ago
pvc-d5b3bad7-f1de-4eba-ab0d-d671bf4ff84e   mongo    mongodb-data-3   10G        released   RWO            24m ago
pvc-88f43b37-f201-4478-8e6f-0ed875f2c791   mongo    mongodb-data-0   10G        bound      RWO            84m ago

> acorn rm -v pvc-f457051e-19a4-4d85-8ca0-046b60df060b pvc-d5b3bad7-f1de-4eba-ab0d-d671bf4ff84e
pvc-f457051e-19a4-4d85-8ca0-046b60df060b
pvc-d5b3bad7-f1de-4eba-ab0d-d671bf4ff84e
```

### Trigger election manually

```shell

acorn exec -c mongodb-0 [APP-NAME]

mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'rs.stepDown()'

```
### Convert standalone to replica set

- Update the acorn app using the following command:
```shell
acorn update [APP-NAME] --replicas 1 --is-replica-set true --hidden-replicas 0
```
- Initiate the new replica set:
```shell
acorn exec -c mongodb-0 [APP-NAME]

mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'rs.initiate()'
```
- Check the status of the replica set:
```shell
acorn exec -c mongodb-0 [APP-NAME]

mongosh admin --host $MONGODB_SERVER_LIST --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD --eval 'rs.status()'
```

### Backups

#### Enabling scheduled Backups

If you would like to back up your database, you can launch with or update the app with a `--backup-schedule`. The backup schedule is in cron format.

Here is an example of how you could do daily backups:
`acorn run [MONGODB_ACORN_IMAGE] --backup-schedule "0 0 * * *"`

If you would like to add backups to an already running cluster, you can do:
`acorn update [APP-NAME] --backup-schedule "0 0 * * *"`

Backups are run from a pod that will mount `mongodb-backup` volume. The job uses `mongodump` utility and exports binary database dump compressed by Gzip to `mongodb-backup` volume.
You can also backup a specific database or collection by specifying `--backup-db` and `--backup-collection`.

#### Listing available backups

To see which backups are available, you can list them by exposing the content of the `backup-list` secret.

```shell
> acorn secret expose APP-NAME.backup-list
NAME                TYPE        KEY       VALUE
backup-list-ct2qx   generated   content   total 36
drwx------ 2 root root 16384 Sep 17 14:36 lost+found
-rw-r--r-- 1 1001 root  2553 Sep 17 14:44 mongodbdump.2022-09-17T14:44:08Z.gz
-rw-r--r-- 1 1001 root  2550 Sep 17 14:46 mongodbdump.2022-09-17T14:46:09Z.gz
-rw-r--r-- 1 1001 root  2557 Sep 17 14:48 mongodbdump.2022-09-17T14:48:09Z.gz
-rw-r--r-- 1 1001 root  2555 Sep 17 14:50 mongodbdump.2022-09-17T14:50:05Z.gz
-rw-r--r-- 1 1001 root  2553 Sep 17 14:52 mongodbdump.2022-09-17T14:52:05Z.gz
```

#### Restoring from a backup

Only follow this procedure if you are certain you need to restore data. This procedure will cause ALL data to be LOST from the time of the backup.

To restore from backup, first identify which backup you want to restore from in the backup list above.

Update the app:
`acorn update [APP-NAME] --backup-to-restore [BACKUP FILE NAME]`

This will initiate a `restore-from-backup` job which executes `mongorestore`.

#### Configuring retention policy
If you would like to keep backups for a specific amount of days, you can configure `--backup-retain-days`.
```shell
acorn update [APP-NAME] --backup-retain-days 15
```
This will keep backups for 15 days.


### Entering diagnostic mode
Sometimes, due to unexpected issues, installations can become corrupted and get stuck in a `CrashLoopBackOff` restart loop. In these situations, it may be necessary to access the containers and perform manual operations to troubleshoot and fix the issues. To ease this task, this acorn provides the diagnostic mode that will deploy all the containers with all probes disabled and override all commands and arguments with `sleep infinity`.

To activate the diagnostic mode, update the acorn app with the following command.
```shell
acorn update [APP-NAME] --diagnostic-mode true
```
Once the acorn app has been updated, access the containers by executing the following command:
```shell
acorn exec -c mongodb-0 [APP-NAME]
```
You can access any container by changing `mongodb-0` with desired container name.

## TODOs

* TLS support
* Expose MongoDB outside of k8s cluster