import "list"

import "text/tabwriter"

import "strings"

args: deploy: {
	// Specify the username of db user
	dbUserName: string | *""

	// Specify the name of the database to create
	dbName: string | *"acorn"

	// Galera cluster name
	clusterName: string | *"galera"

	// Number of nodes to run in the galera cluster
	replicas: int | *3

	// Put the cluster into recovery mode.
	recovery: bool | *false

	// Server to have boot strap a new cluster
	bootStrapIndex: int | *2

	// When recovering the cluster this will force safe_to_bootstrap in grastate.dat for the bootStrapIndex node.
	forceRecover: bool | *false
}

for i in list.Range(0, args.deploy.replicas, 1) {
	containers: {
		"mariadb-\(i)": {
			image: "mariadb:10.6.8-focal"
			ports: [
				"4567:4567",
				"4568:4568",
				"4444:4444",
			]
			expose: "3306:3306"
			env: {
				"MARIADB_ROOT_PASSWORD": "secret://root-credentials/password?onchange=no-action"
				"MARIADB_USER":          "secret://db-user-credentials/username?onchange=no-action"
				"MARIADB_PASSWORD":      "secret://db-user-credentials/password?onchange=no-action"
				"MARIADB_DATABASE":      "\(args.deploy.dbName)"
				"MY_NAME":               "mariadb-\(i)"
			}
			dirs: {
				"/var/lib/mysql": "volume://mysql-data-\(i)"
			}
			files: {
				"/docker-entrypoint-initdb.d/create_backup_user.sql": "secret://create-backup-user/template?onchange=no-action"
			}
			if args.deploy.recovery {
				command: ["--wsrep-recover"]
				if args.deploy.forceRecover && args.deploy.bootStrapIndex == i {
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

			if !args.deploy.recovery && i == args.deploy.bootStrapIndex {
				command: ["--wsrep-new-cluster"]
			}

			// Shut off health checks in a broken state to keep pods up longer
			if !args.deploy.recovery {
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

	volumes: {
		"mysql-data-\(i)": {}
	}
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
			username: "\(args.deploy.dbUserName)"
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
}

// Write configuration blocks
for section, configBlock in localData.mariadbConfig {
	secrets: {
		"\(section)-config": {
			type: "template"
			data: template: "[\(section)]\n" +
				tabwriter.Write([ for parameter, value in configBlock {"\(parameter)=\(value)"}])
		}
	}
	containers: [Name= =~"mariadb"]: {
		files: {
			"/etc/mysql/mariadb.conf.d/\(section).cnf": "secret://\(section)-config/template?onchange=no-action"
		}
	}
}

localData: {
	mariadbConfig: {
		client: {
			port:   3306
			socket: "/run/mysqld/mysqld.sock"
		}
		mysqld: {
			port:                           3306
			socket:                         "/run/mysqld/mysqld.sock"
			bind_address:                   "0.0.0.0"
			default_storage_engine:         "InnoDB"
			collation_server:               "utf8_unicode_ci"
			init_connect:                   "'SET NAMES utf8'"
			character_set_server:           "utf8"
			key_buffer_size:                "32M"
			myisam_recover_options:         "FORCE,BACKUP"
			max_allowed_packet:             "16M"
			max_connect_errors:             1000000
			log_bin:                        "mysql-bin"
			expire_logs_days:               14
			sync_binlog:                    0
			tmp_table_size:                 "32M"
			max_heap_table_size:            "32M"
			query_cache_type:               1
			query_cache_limit:              "4M"
			query_cache_size:               "256M"
			max_connections:                500
			thread_cache_size:              50
			open_files_limit:               65535
			table_definition_cache:         4096
			table_open_cache:               4096
			innodb:                         "FORCE"
			innodb_strict_mode:             1
			innodb_doublewrite:             1
			innodb_flush_method:            "O_DIRECT"
			innodb_log_file_size:           "128M"
			innodb_flush_log_at_trx_commit: 1
			innodb_file_per_table:          1
			innodb_buffer_pool_size:        "2G"
			slow_query_log:                 1
			log_queries_not_using_indexes:  1
		}
		galera: {
			wsrep_on:                       "ON"
			wsrep_provider:                 "/usr/lib/libgalera_smm.so"
			wsrep_cluster_name:             "\(args.deploy.clusterName)"
			wsrep_cluster_address:          "gcomm://" + strings.Join([ for i in list.Range(0, args.deploy.replicas, 1) {"mariadb-\(i)"}], ",")
			wsrep_sst_method:               "mariabackup"
			wsrep_sst_auth:                 "${secret://backup-user-credentials/username}:${secret://backup-user-credentials/password}"
			binlog_format:                  "row"
			default_storage_engine:         "InnoDB"
			wsrep_slave_threads:            4
			innodb_flush_log_at_trx_commit: 2
			innodb_autoinc_lock_mode:       2
			wsrep_replicate_myisam:         "ON"
		}
	}
}
