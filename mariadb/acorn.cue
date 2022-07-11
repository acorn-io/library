import "list"

import "text/tabwriter"

import "strings"

args: {
	// Specify the username of db user
	dbUserName: string | *""

	// Specify the name of the database to create. Default(acorn)
	dbName: string | *"acorn"

	// Galera: cluster name
	clusterName: string | *"galera"

	// Number of nodes to run in the galera cluster. Default (1)
	replicas: int | *1

	// Run cluster into recovery mode.
	recovery: bool | *false

	// Set server to boot strap a new cluster. Default (0)
	bootStrapIndex: int | *0

	// When recovering the cluster this will force safe_to_bootstrap in grastate.dat for the bootStrapIndex node.
	forceRecover: bool | *false

	// User provided MariaDB config
	customMariadbConfig: {...} | *{}

	// Backup Schedule
	backupSchedule: string | *""

	// Restore from Backup. Takes a backup file name
	restoreFromBackup: string | *""
}

profiles: {
	build: {
		backupSchedule:    "* * * * *"
		restoreFromBackup: "not-a-real-backup"
		recovery:          true
	}
}

for i in list.Range(0, args.replicas, 1) {
	containers: {
		"mariadb-\(i)": {
			image: "mariadb:10.6.8-focal"
			ports: [
				"4567:4567",
				"4568:4568",
				"4444:4444",
			]
			alias:  "mariadb"
			expose: "3306:3306"
			env: {
				"MARIADB_ROOT_PASSWORD": "secret://root-credentials/password?onchange=no-action"
				"MARIADB_USER":          "secret://db-user-credentials/username?onchange=no-action"
				"MARIADB_PASSWORD":      "secret://db-user-credentials/password?onchange=no-action"
				"MARIADB_DATABASE":      "\(args.dbName)"
				"MY_NAME":               "mariadb-\(i)"
			}
			dirs: {
				"/var/lib/mysql": "volume://mysql-data-\(i)"
			}
			files: {
				"/docker-entrypoint-initdb.d/create_backup_user.sql": "secret://create-backup-user/template?onchange=no-action"
			}
			if args.recovery {
				command: ["--wsrep-recover"]
				if args.forceRecover && args.bootStrapIndex == i {
					sidecars: {
						"recovery-\(i)": {
							image: "mariadb:10.6.8-focal"
							entrypoint: [
								"/acorn/set_safe_to_bootstrap.sh",
							]
							files: {
								"/acorn/set_safe_to_bootstrap.sh": """
                                #!/bin/bash
                                sed -i 's/\\(safe_to_bootstrap:\\) 0/\\1 1/' /var/lib/mysql/grastate.dat
                                if [ "$?" -ne "0" ]; then
                                  echo "unable to update grastate.dat"
                                  exit 0
                                fi
                                """
							}
							dirs: {
								"/var/lib/mysql": "volume://mysql-data-\(i)"
							}
						}
					}
				}
			}

			if !args.recovery && i == args.bootStrapIndex {
				command: ["--wsrep-new-cluster"]
			}

			// Shut off health checks in a broken state to keep pods up longer
			if !args.recovery {
				probes: [
					{
						type:                "liveness"
						initialDelaySeconds: 120
						periodSeconds:       10
						timeoutSeconds:      1
						successThreshold:    1
						failureThreshold:    3
						exec: command: [
							"bash",
							"-ec",
							"exec",
							"mysql",
							"-uroot",
							"-p${MARIADB_ROOT_PASSWORD}",
							"-e",
							"select * from mysql.wsrep_cluster_members;",
						]
					},
					{
						type:                "readiness"
						initialDelaySeconds: 30
						periodSeconds:       10
						timeoutSeconds:      1
						successThreshold:    1
						failureThreshold:    3
						exec: command: [
							"bash",
							"-ec",
							"exec",
							"mysqladmin",
							"status",
							"-uroot",
							"-p\"${MARIADB_ROOT_PASSWORD}\"",
						]
					},
					{
						type:             "startup"
						periodSeconds:    10
						timeoutSeconds:   1
						failureThreshold: 30
						exec: command: [
							"bash",
							"-ec",
							"exec",
							"mysqladmin",
							"status",
							"-uroot",
							"-p\"${MARIADB_ROOT_PASSWORD}\"",
						]
					},
				]
			}
		}
	}

	if i != 0 {
		volumes: {
			"mysql-data-\(i)": {}
		}
	}
}

// This is a special volume, and should always be defined. Needs to exist when scale is 0.
volumes: {
	"mysql-data-0": {}
}

if args.backupSchedule != "" {
	jobs: {
		"backup": {
			image: "mariadb:10.6.8-focal"
			command: ["/acorn/scripts/backup.sh", "mariadb-\(localData.backupReplica)"]
			dirs: {
				"/var/lib/mysql": "volume://mysql-data-\(localData.backupReplica)"
				"/backups":       "volume://mysql-backup-vol"
			}
			env: {
				"MARIADB_BACKUP_USER":     "secret://backup-user-credentials/username"
				"MARIADB_BACKUP_PASSWORD": "secret://backup-user-credentials/password"
			}
			schedule: args.backupSchedule
			dirs: {
				"/acorn/scripts/": "./scripts"
			}
		}
	}
	secrets: {
		"backup-list": {
			type: "generated"
			params: {
				job: "backup"
			}
		}
	}
}

if args.restoreFromBackup != "" {
	jobs: {
		"restore-from-backup": {
			image: "mariadb:10.6.8-focal"
			dirs: {
				"/var/lib/mysql":  "volume://mysql-data-\(localData.backupReplica)"
				"/backups":        "volume://mysql-backup-vol"
				"/scratch":        "volume://restore-scratch"
				"/acorn/scripts/": "./scripts"
			}
			env: {
				"MARIADB_BACKUP_USER":     "secret://backup-user-credentials/username"
				"MARIADB_BACKUP_PASSWORD": "secret://backup-user-credentials/password"
			}
			command: ["/acorn/scripts/restore.sh", "\(args.restoreFromBackup)"]
		}
	}
	volumes: "restore-scratch": {}
}

volumes: {
	"mysql-backup-vol": {}
}

secrets: {
	"root-credentials": {
		type: "basic"
		data: {
			username: "root"
			password: ""
		}

	}
	"db-user-credentials": {
		type: "basic"
		data: {
			username: "\(args.dbUserName)"
			password: ""
		}
	}
	"backup-user-credentials": {
		type: "basic"
		data: {
			username: "mariabackup"
			password: ""
		}
	}
	"create-backup-user": {
		type: "template"
		data: template: """
			CREATE USER '${secret://backup-user-credentials/username}'@'localhost' IDENTIFIED BY '${secret://backup-user-credentials/password}';
			GRANT RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR ON *.* TO '${secret://backup-user-credentials/username}'@'localhost';
			CREATE USER '${secret://backup-user-credentials/username}'@'%' IDENTIFIED BY '${secret://backup-user-credentials/password}';
			GRANT RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR ON *.* TO '${secret://backup-user-credentials/username}'@'%';
			"""
	}

	// Provides user a target to bind in secret data
	"user-secret-data": type: "opaque"
}

// Write configuration blocks
let mConfig = localData.mariadbConfig
for replica in list.Range(0, args.replicas, 1) {
	for section, configBlock in mConfig {
		if section != "replicas" {
			secrets: {
				"mariadb-\(replica)-\(section)-config": {
					type: "template"
					if !(mConfig.replicas["mariadb-\(replica)"]["\(section)"] != _|_) {
						data: template: "[\(section)]\n" +
							tabwriter.Write([ for parameter, value in configBlock {"\(parameter)=\(value)"}])
					}
					if mConfig.replicas["mariadb-\(replica)"]["\(section)"] != _|_ {
						data: template: "[\(section)]\n" +
							tabwriter.Write([ for parameter, value in configBlock & mConfig.replicas["mariadb-\(replica)"]["\(section)"] {"\(parameter)=\(value)"}])
					}
				}
			}
			containers: [Name= =~"mariadb-\(replica)"]: {
				files: {
					"/etc/mysql/mariadb.conf.d/\(section).cnf": "secret://mariadb-\(replica)-\(section)-config/template?onchange=no-action"
				}
			}
		}
	}
}

localData: {
	if args.replicas == 0 {
		backupReplica: 0
	}
	if args.replicas > 0 {
		backupReplica: args.replicas - 1
	}
	mariadbConfig: args.customMariadbConfig & {
		client: {
			port:   3306
			socket: "/run/mysqld/mysqld.sock"
		}
		mysqld: {
			port:                          3306
			socket:                        "/run/mysqld/mysqld.sock"
			bind_address:                  "0.0.0.0"
			default_storage_engine:        string | *"InnoDB"
			collation_server:              string | *"utf8_unicode_ci"
			init_connect:                  string | *"'SET NAMES utf8'"
			character_set_server:          string | *"utf8"
			key_buffer_size:               string | *"32M"
			myisam_recover_options:        string | *"FORCE,BACKUP"
			max_allowed_packet:            string | *"16M"
			max_connect_errors:            1000000
			log_bin:                       string | *"mysql-bin"
			expire_logs_days:              int | *14
			sync_binlog:                   int | *0
			tmp_table_size:                string | *"32M"
			max_heap_table_size:           string | *"32M"
			query_cache_type:              int | *1
			query_cache_limit:             string | *"4M"
			query_cache_size:              string | *"256M"
			max_connections:               int | *500
			thread_cache_size:             int | *50
			open_files_limit:              int | *65535
			table_definition_cache:        int | *4096
			table_open_cache:              int | *4096
			innodb:                        string | *"FORCE"
			innodb_strict_mode:            int | *1
			innodb_doublewrite:            int | *1
			innodb_flush_method:           string | *"O_DIRECT"
			innodb_log_file_size:          string | *"128M"
			innodb_file_per_table:         int | *1
			innodb_buffer_pool_size:       string | *"2G"
			slow_query_log:                int | *1
			log_queries_not_using_indexes: int | *1
		}
		galera: {
			wsrep_on:                       "ON"
			wsrep_provider:                 "/usr/lib/libgalera_smm.so"
			wsrep_cluster_name:             "\(args.clusterName)"
			wsrep_cluster_address:          "gcomm://" + strings.Join([ for i in list.Range(0, args.replicas, 1) {"mariadb-\(i)"}], ",")
			wsrep_sst_method:               "mariabackup"
			wsrep_sst_auth:                 "${secret://backup-user-credentials/username}:${secret://backup-user-credentials/password}"
			binlog_format:                  "row"
			default_storage_engine:         "InnoDB"
			wsrep_slave_threads:            4
			innodb_flush_log_at_trx_commit: 2
			innodb_autoinc_lock_mode:       2
			wsrep_replicate_myisam:         "ON"
		}
		replicas: {}
	}
}
