import "text/tabwriter"

import "list"

// collision in the token secret
let deployParams = params.deploy
params: {
	deploy: {
		// Sets the requirepass value otherwise one is randomly generated
		redisPassword: *"" | string

		// Redis replicas per master. To run in stand alone set to 0 
		redisReplicaCount:  int | *1
	}
}

// Sets up the data directory volume so that it is either ephemeral or bound to a volume.
containers: {
	redis: {
		image:   "redis:7-alpine"
		publish: "6379:6379/tcp"
		cmd: ["/etc/redis/6379.conf"]
		files: {
			"/etc/redis/6379.conf": "secret://redis-leader-config/template"
		}
		dirs: {
			"/data": "volume://redis-leader-data-dir-0"
		}
	}
}

volumes: {
	"redis-leader-data-dir-0": {
		accessModes: ["readWriteOnce"]
	}
}

for i in list.Range(0, deployParams.redisReplicaCount, 1) {
	containers: {
		"redis-follower-\(i)": {
			image:   "redis:7-alpine"
			scale:   2
			publish: "6379:6379/tcp"
			cmd: ["/etc/redis/6379.conf"]
			files: {
				"/etc/redis/6379.conf": "secret://redis-follower-config/template"
			}
			dirs: {
				"/data": "volume://redis-follower-data-\(i)"
			}
		}
	}

	volumes: {
		"redis-follower-data-\(i)": {
			accessModes: ["readWriteOnce"]
		}
	}
}

if deployParams.redisReplicaCount != 0 {
	secrets: {
		"redis-follower-config": {
			type: "template"
			data: {
				template: tabwriter.Write([ for i, v in followerConfigTemplate {"\(i) \(v)"}])
			}
		}
	}
	data: {
		redisFollowerConfig: {
			masterauth:        "${secret://redis-auth/token}"
			slaveof:           "redis 6379"
			"slave-read-only": "yes"
		}
	}
	let followerConfigTemplate = data.redisCommonConfig & data.redisFollowerConfig
}

secrets: {
	"redis-auth": {
		type: "token"
		params: {
			length: 32
		}
		data: {
			token: "\(deployParams.redisPassword)"
		}

	}
	"redis-leader-config": {
		type: "template"
		data: {
			template: tabwriter.Write([ for i, v in leaderConfigTemplate {"\(i) \(v)"}])
		}
	}
}

let leaderConfigTemplate = data.redisCommonConfig & data.redisLeaderConfig

data: {
	storageDef: {
		type:        *"ephemeral" | "volume"
		queryString: *"" | string
	}
	redisCommonConfig: {
		requirepass: "${secret://redis-auth/token}"
		port:        6379
		dir:         "/data"
		"######":    " ROLE CONFIG ######"
	}
	redisLeaderConfig: {
		"tcp-keepalive": 60
	}
}
