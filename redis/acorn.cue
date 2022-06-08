import "text/tabwriter"

import "list"

// Setting common config settings
containers: [Name= =~"redis"]: {
	image: "redis:7-alpine"
	cmd: ["/etc/redis/6379.conf"]
	// std port should be exposed to be consumed outside the acorn
	if deployParams.redisLeaderCount > 1 {
		ports: data.busPort
	}
}
// This goes away once we have expose and can publish at run time
containers: [Name= =~"redis-[0-9]"]: publish:        data.stdPort
containers: [Name= =~"redis-follower-[0-9]"]: ports: data.stdPort

volumes: [Name= =~"redis"]: accessModes: ["readWriteOnce"]
secrets: [Name= =~"redis-[a-zA-Z]*-config"]: type: "template"
jobs: [Name= =~"redis"]: image:                    "redis:7-alpine"

// collision in the token secret
let deployParams = params.deploy
params: {
	deploy: {
		// Sets the requirepass value otherwise one is randomly generated
		redisPassword: *"" | string

		// Redis replicas per leader. To run in stand alone set to 0 
		redisReplicaCount: int | *1

		// Redis leader replica count. Setting this value above 1 will configure Redis cluster.
		redisLeaderCount: int | *1
	}
}

data: followerCount: [
			if deployParams.redisLeaderCount > 1 {0},
			if deployParams.redisLeaderCount == 1 {deployParams.redisReplicaCount},
][0]

data: clusterReplicationFactor: [
				if deployParams.redisLeaderCount == 1 {1},
				if deployParams.redisReplicaCount > 0 {deployParams.redisReplicaCount + 1},
				1,
][0]

data: {
	redisCommonConfig: {
		requirepass: "${secret://redis-auth/token}"
		port:        6379
		dir:         "/data"
		"######":    " ROLE CONFIG ######"
	}
	redisLeaderConfig: "tcp-keepalive": 60
	stdPort: ["6379:6379/tcp"]
	busPort: ["16379:16379/tcp"]
	clusterReplicationFactor: int & >0 | *1
	serverCount:              deployParams.redisLeaderCount * data.clusterReplicationFactor
}

secrets: {
	"redis-auth": {
		type: "token"
		params: length: 32
		data: token:    "\(deployParams.redisPassword)"
	}
	"redis-leader-config": data: template: tabwriter.Write([ for i, v in leaderConfigTemplate {"\(i) \(v)"}])
}

// Allows use secret template without name collision
let leaderConfigTemplate = data.redisCommonConfig & data.redisLeaderConfig

// Sets up the data directory volume so that it is either ephemeral or bound to a volume.
for i in list.Range(0, data.serverCount, 1) {
	containers: {
		"redis-\(i)": {
			alias: "redis"
			files: {
				"/etc/redis/6379.conf": "secret://redis-leader-config/template"
			}
			dirs: {
				"/data": "volume://redis-leader-data-dir-\(i)"
			}
		}
	}
	volumes: "redis-leader-data-dir-\(i)": {}
}

if deployParams.redisLeaderCount > 1 {
	data: redisLeaderConfig: {
		"cluster-enabled":      "yes"
		"cluster-config-file":  "nodes.conf"
		"cluster-node-timeout": 5000
		appendonly:             "yes"
	}
	jobs: {
		"redis-init-cluster": {
			env: {
				"REDISCLI_AUTH": "secret://redis-auth/token"
			}
			dirs: {
				"/acorn": "ephemeral://valid-name"
			}
			files: {
				"/acorn/create-cluster-init-script.sh": """
				#!/bin/sh

				cluster_init_script=/acorn/redis-cluster-init.sh

				cat > $cluster_init_script <<EOF
				#!/bin/bash
				echo "yes" |redis-cli --cluster create $(for i in $(seq 0 \(data.serverCount-1));do echo -n "redis-${i}:6379 ";done) --cluster-replicas \(deployParams.redisReplicaCount)
				EOF

				chmod u+x ${cluster_init_script}

				/bin/sh ${cluster_init_script}
				"""
			}
			cmd: ["/bin/sh", "/acorn/create-cluster-init-script.sh"]
		}
	}
}

for i in list.Range(0, data.followerCount, 1) {
	containers: {
		"redis-follower-\(i)": {
			files: {
				"/etc/redis/6379.conf": "secret://redis-follower-config/template"
			}
			dirs: {
				"/data": "volume://redis-follower-data-\(i)"
			}
		}
	}
	volumes: "redis-follower-data-\(i)": {}
}

if data.followerCount != 0 {
	let followerConfigTemplate = data.redisCommonConfig & data.redisFollowerConfig
	data: redisFollowerConfig: {
		masterauth:        "${secret://redis-auth/token}"
		slaveof:           "redis 6379"
		"slave-read-only": "yes"
	}
	secrets: "redis-follower-config": data: template: tabwriter.Write([ for i, v in followerConfigTemplate {"\(i) \(v)"}])
}
