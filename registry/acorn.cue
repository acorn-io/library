import "encoding/yaml"

containers: {
	registry: {
		image:  "registry:2.8.1"
		scale:  args.deploy.replicas
		expose: "5000:5000/http"
		if args.deploy.enableMetrics {
			ports: "5001:5001/http"
		}
		files: {
			"/auth/htpasswd":                  "secret://generated-htpasswd/content?onchange=no-action"
			"/etc/docker/registry/config.yml": "secret://registry-config/template?onchange=redeploy"
		}
		probes: [
			{
				type: "readiness"
				http:
					url: "http://localhost:5000"
			},
		]
	}
	if args.deploy.storageCache == "redis" {
		redis: {
			image: "redis"
			ports: {
				"6379:6379/tcp"
			}
		}
	}
}

jobs: {
	"htpasswd-create": {
		env: {
			"USER": "secret://registry-user-creds/username"
			"PASS": "secret://registry-user-creds/password"
		}
		entrypoint: "/bin/sh -c"
		image:      "httpd:2"
		// Output of a generated secret needs to be placed in the file /run/secrets/output.
		cmd: ["htpasswd -Bbc /run/secrets/output $USER $PASS"]
	}
}

args: {
	deploy: {
		//Cache backend for blobdescriptor default 'inmemory' you can also use redis
		storageCache: *"inmemory" | "redis"

		//Enable metrics endpoint
		enableMetrics: *true | false | bool

		//This is the username allowed to login and push items to the registry. Default is randomly generated and can be obtained from the secret"
		htpasswdUsername: *"" | string

		//This is the password to login and push items to the registry. Default is randomly generated and can be obtained from the secret"
		htpasswdPassword: *"" | string

		//Number of registry containers to run.
		replicas: int | *1

		//Provide the complete storage configuration blob in registry config format.
		storageConfig: {}

		//Provide the complete auth configuration blob in registry config format.
		authConfig: {}

		//Provide additional configuration for the registry
		extraRegistryConfig: {}
	}
}

secrets: {
	"registry-user-creds": {
		type: "basic"
		data: {
			username: "\(args.deploy.htpasswdUsername)"
			password: "\(args.deploy.htpasswdPassword)"
		}
	}
	"generated-htpasswd": {
		type: "generated"
		params: {
			job: "htpasswd-create"
		}
	}
	"registry-config": {
		type: "template"
		data: {template: yaml.Marshal(localData.registryConfig)}
	}
	"registry-http-secret": type: "token"
	"user-secret-data": type:     "opaque"
}

localData: storageDriver: args.deploy.storageConfig
if len(localData.storageDriver) == 0 {
	localData: storageDriver: filesystem: rootdirectory: "/var/lib/registry"
}

localData: authConfig: args.deploy.authConfig
if len(localData.authConfig) == 0 {
	localData: authConfig: htpasswd: realm: "Registry Realm"
	localData: authConfig: htpasswd: path:  "/auth/htpasswd"
}

localData: registryConfig: {
	version: "0.1"
	log: fields: service:           "registry"
	storage: cache: blobdescriptor: args.deploy.storageCache
	storage: localData.storageDriver
	auth:    localData.authConfig
	http: {
		addr:   ":5000"
		secret: "${secret://registry-http-secret/token}"
		headers: {
			"X-Content-Type-Options": ["nosniff"]
		}
	}
	health: {
		storagedriver: {
			enabled:   true
			interval:  "10s"
			threshold: 3
		}
	}
} & args.deploy.extraRegistryConfig

if args.deploy.storageCache == "redis" {
	localData: registryConfig: redis: {
		addr:         "redis:6379"
		db:           0
		dialtimeout:  "10ms"
		readtimeout:  "10ms"
		writetimeout: "10ms"
		pool: {
			maxidle:     16
			maxactive:   64
			idletimeout: "300s"
		}
	}
}
if args.deploy.enableMetrics {
	localData: registryConfig: metricsConfig: {
		debug: {
			addr: "0.0.0.0:5001"
			prometheus: {
				enabled: true
				path:    "/metrics"
			}
		}
	}
}
