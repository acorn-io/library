import "text/tabwriter"

import "list"

// prevents collision when using in token secrets
args: {
	deploy: {
		// Sets the requirepass value otherwise one is randomly generated
		redisPassword: *"" | string

		// Redis replicas per leader. To run in stand alone set to 0 
		redisReplicaCount: int | *1

		// Redis leader replica count. Setting this value 3 and above will configure Redis cluster.
		redisLeaderCount: int | *1

		// User provided configuration for leader and cluster servers
		redisLeaderConfig: {}

		// User provided configuration for leader and cluster servers
		redisFollowerConfig: {}
	}
}

// Leaders
for l in list.Range(0, args.deploy.redisLeaderCount, 1) {
	// Followers
	for f in list.Range(0, args.deploy.redisReplicaCount+1, 1) {
		containers: {
			"redis-\(l)-\(f)": {
				image: "redis:7-alpine"
				cmd: ["/etc/redis/6379.conf"]
				if args.deploy.redisLeaderCount > 1 {
					ports: "16379:16379/tcp"
				}
				expose: "6379:6379/tcp"
				env: {
					"REDISCLI_AUTH": "secret://redis-auth/token"
				}
				if args.deploy.redisLeaderCount > 1 || f == 0 {
					files: {
						"/etc/redis/6379.conf": "secret://redis-leader-config/template"
					}
				}
				if args.deploy.redisLeaderCount == 1 && f > 0 {
					files: {
						"/etc/redis/6379.conf": "secret://redis-follower-config/template"
					}
				}
				dirs: {
					"/data":  "volume://redis-data-dir-\(l)-\(f)"
					"/acorn": "ephemeral://acorn-data-\(l)-\(f)"
				}
			}
		}

		volumes: "redis-data-dir-\(l)-\(f)": accessModes: ["readWriteOnce"]
	}
}

if args.deploy.redisReplicaCount != 0 {
	let followerConfigTemplate = localData.redis.commonConfig & localData.redis.followerConfig & args.deploy.redisFollowerConfig
	localData: redis: followerConfig: {
		slaveof:           "redis-0-0 6379"
		"slave-read-only": "yes"
	}
	secrets: "redis-follower-config": {
		type: "template"
		data: template: tabwriter.Write([ for i, v in followerConfigTemplate {"\(i) \(v)"}])
	}
}
// End follower replica block

let leaderConfigTemplate = localData.redis.commonConfig & localData.redis.leaderConfig & args.deploy.redisLeaderConfig
localData: {
	redis: {
		commonConfig: {
			requirepass: "${secret://redis-auth/token}"
			masterauth:  "${secret://redis-auth/token}"
			port:        6379
			dir:         "/data"
			"######":    " ROLE CONFIG ######"
		}
		leaderConfig: "tcp-keepalive": int | *60
		followerConfig: {...} | *{}
	}
	serverCount: args.deploy.redisLeaderCount + (args.deploy.redisLeaderCount * args.deploy.redisReplicaCount)
}

secrets: {
	"redis-auth": {
		type: "token"
		params: length: 32
		data: token:    "\(args.deploy.redisPassword)"
	}
	"redis-leader-config": {
		type: "template"
		data: template: tabwriter.Write([ for i, v in leaderConfigTemplate {"\(i) \(v)"}])
	}
	// Provides user a target to bind in secret data
	"redis-user-data": type: "opaque"
}

if args.deploy.redisLeaderCount > 1 {
	localData: redis:
		leaderConfig: {
			"cluster-enabled":      "yes"
			"cluster-config-file":  "nodes.conf"
			"cluster-node-timeout": int | *5000
			appendonly:             "yes"
		}
	jobs: {
		"redis-init-cluster": {
			image: "redis:7-alpine"
			env: {
				"REDISCLI_AUTH": "secret://redis-auth/token"
			}
			dirs: {
				"/acorn": "ephemeral://valid-name"
			}
			files: {
				"acorn/create-cluster-init-script.sh": "secret://cluster-init-script/template"
			}
			cmd: ["/bin/sh", "/acorn/create-cluster-init-script.sh", "6"]
		}
	}
	// Only use this for the init template
	secrets: {
		"cluster-init-script": {
			type: "template"
			data: {
				template: """
				#!/bin/sh

				set -e

				replica_count=\(args.redisReplicaCount)
				leader_server_count=\(args.redisLeaderCount)
				total_server_count=\(localData.serverCount)


				cluster_init_script=/acorn/redis-cluster-init.sh

				# wait until services become available
				for l in $(seq 0 \(args.redisLeaderCount-1)); do
				  for f in $(seq 0 \(args.redisReplicaCount-1)); do
				    echo "checking redis-${l}-${f}"
				  	until timeout -s 3 5 redis-cli -h redis-${l}-${f} -p 6379 ping; do echo "waiting...";sleep 5;done
				  done
				done

				known_nodes=$(redis-cli -h redis-0-0 cluster info |grep cluster_known_nodes|tr -d '[:space:]'|cut -d: -f2)
				cluster_size=$(redis-cli -h redis-0-0 cluster info |grep cluster_size|tr -d '[:space:]'|cut -d: -f2)
				if [ "${cluster_size}" -eq "0" ]; then
				  echo "initializing cluster..."
				
				  node_string=
				  for l in $(seq 0 \(args.redisLeaderCount-1));do
				    for f in $(seq 0 \(args.redisReplicaCount));do 
				      node_string="${node_string} redis-${l}-${f}:6379 "
				    done
				  done

				  echo "yes" | redis-cli --cluster create ${node_string} --cluster-replicas \(args.redisReplicaCount)

				  # Exit because we just setup the cluster and there is nothing else to do
				  # in this run of the code.
				  echo "Cluster initialized..."
				  exit 0
				fi

				echo "Cluster already initialized..."
				if [ "$(redis-cli -h redis-0-0 cluster info |grep cluster_state|tr -d '[:space:]'|cut -d: -f2)" == "fail" ]; then
				  echo "Cluster in failed state exiting out"
				  exit 1
				fi

				if [ "${total_server_count}" -eq "${known_nodes}" ] && [ "${leader_server_count}" -eq "{cluster_size}" ]; then
					echo "Scale is set... exiting"
					exit 0
				fi

				server_diff=$(expr ${total_server_count} - ${known_nodes})
				if [ "${server_diff}" -lt "0" ]; then
				  echo "this is a scale down event.. manual intervention required"
				  exit 0
				fi

				offset=$(expr ${cluster_size} - 0)
				for l in $(seq ${offset} $(expr ${leader_server_count} - 1)); do
				   for f in $(seq 0 \(args.redisReplicaCount)); do
				     if [ "${f}" -ne "0" ];then
					 	m_id=$(redis-cli -h redis-${l}-0 cluster nodes|grep myself|awk '{print $1}')
					 	replication_flag="--cluster-slave --cluster-master-id ${m_id}"
					 fi
					 redis-cli --cluster add-node redis-${l}-${f}:6379 redis-0-0:6379 ${replication_flag}
					 sleep 5
					 replication_flag=
				   done
				done
				# Let cluster quisce for a few seconds
				sleep 5
				redis-cli --cluster rebalance redis-0-0:6379 --cluster-use-empty-masters

				"""
			}
		}
	}
}

// Add healthchecks and scripts for all Redis containers regardless of type
containers: [Name= =~"redis"]: {
	probes: [
		{
			type:                "readiness"
			initialDelaySeconds: 5
			periodSeconds:       5
			timeoutSeconds:      2
			successThreshold:    1
			failureThreshold:    5
			exec: command: ["/bin/sh", "/acorn/redis-ping-local-readiness.sh", "1"]
		},
		{
			type:                "liveness"
			initialDelaySeconds: 5
			periodSeconds:       5
			timeoutSeconds:      6
			successThreshold:    1
			failureThreshold:    5
			exec: command: ["/bin/sh", "/acorn/redis-ping-local-liveness.sh", "5"]
		},
	]

	files: {
		"/acorn/redis-ping-local-readiness.sh": """
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
			"""
		"/acorn/redis-ping-local-liveness.sh": """
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
			"""
	}
}
