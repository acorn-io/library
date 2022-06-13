import "encoding/yaml"

containers: {
	registry: {
		image:   "registry:2.8.1"
		scale:   params.deploy.replicas
		publish: "5000:5000/http"
		if params.deploy.enableMetrics {
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
	if params.deploy.storageCache == "redis" {
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

params: {
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
			username: "\(params.deploy.htpasswdUsername)"
			password: "\(params.deploy.htpasswdPassword)"
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
		data: {template: yaml.Marshal(config)}
	}
	"registry-http-secret": type: "token"
	"user-secret-data": type:     "opaque"
}

// This is to work around the data scope
let config = data.registryConfig

data: storageDriver: params.deploy.storageConfig
if len(data.storageDriver) == 0 {
	data: storageDriver: filesystem: rootdirectory: "/var/lib/registry"
}

data: authConfig: params.deploy.authConfig
if len(data.authConfig) == 0 {
	data: authConfig: htpasswd: realm: "Registry Realm"
	data: authConfig: htpasswd: path:  "/auth/htpasswd"
}

data: registryConfig: {
	version: "0.1"
	log: fields: service:           "registry"
	storage: cache: blobdescriptor: params.deploy.storageCache
	storage: data.storageDriver
	auth:    data.authConfig
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
} & params.deploy.extraRegistryConfig

if params.deploy.storageCache == "redis" {
	data: registryConfig: redis: {
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
if params.deploy.enableMetrics {
	data: registryConfig: metricsConfig: {
		debug: {
			addr: "0.0.0.0:5001"
			prometheus: {
				enabled: true
				path:    "/metrics"
			}
		}
	}
}
