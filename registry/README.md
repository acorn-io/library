
# Registry Acorn

---
This Acorn will deploy the official [distribution registry](https://hub.docker.com/_/registry).

## How to use this Acorn

### Pre-req

The OCI registry requires TLS in most cases to work well. With that in mind, you will want to create a TLS secret in your Acorn's namespace with the appropriate SAN.

### Quick start

Run this command in a cluster with Acorn installed:

`acorn run -d <fqdn>:registry acorn-io/library/registry:2.8.1`

This will deploy the registry with `inmemory` cache, filesystem storage, and generated htpasswd user.

To get the username and password:

```shell
> acorn secrets
...
registry-user-creds-<uid>    kubernetes.io/basic-auth    [password username]         2 hours ago
...

> acorn secret expose registry-user-creds-<uid>
NAME                        TYPE                       KEY        VALUE
registry-user-creds-cxzlg   kubernetes.io/basic-auth   password   secretpassword
registry-user-creds-cxzlg   kubernetes.io/basic-auth   username   user
```

You will also want to place a TLS secret in the `acorn` namespace with the `fqdn` in the SANS. That will allow loginging in with Docker CLI using the password.

`docker login -u <user> <fqdn>`

### Available options

```shell

Volumes:   <none>
Secrets:   registry-user-creds, generated-htpasswd, registry-config, registry-http-secret, user-secret-data
Container: registry
Ports:     registry:5000/http

      --auth-config string             Provide the complete auth configuration blob in registry config format.
      --enable-metrics string          Enable metrics endpoint
      --extra-registry-config string   Provide additional configuration for the registry
      --htpasswd-password string       This is the password to login and push items to the registry. Default is randomly generated and can be obtained from the secret"
      --htpasswd-username string       This is the username allowed to login and push items to the registry. Default is randomly generated and can be obtained from the secret"
      --registry-internal-port int     Internal server port defaults to 5000
      --registry-proto string          This is the protocol default is 'http' but 'tcp' is available. For TLS expose on http and add TLS to ingress
      --registry-public-port int       This is the port to publish the registry on
      --storage-cache string           Cache backend for blobdescriptor default 'inmemory' you can also use redis
      --storage-config string          Provide the complete storage configuration blob in registry config format.
```

If you need to provide secret data to user defined configurations, you can create a secret and bind it at runtime to the `user-secret-data` secret. See storage example in the advanced section for reference.

## Advanced Usage

### Specifying Redis for storage cache

#### Internal

To use `redis` as the storage cache launch the acorn with the following options
`acorn run -d <fqdn>:registry acorn-io/library/registry:2.8.1 --storage-cache redis`

This will deploy a Redis container as part of the overall and configure the registry to leverage it.

### Specify user/password to use with built in basic auth

`acorn run -d <fqdn>:registry acorn-io/library/registry:2.8.1 --htpasswd-username <username> [--htpasswd-password <password>]`

If no password is provided, Acorn will generate one and place it in the secret. You can use the method in the quickstart to get the generated password.

### Configure a different storage backend

It is common to use an object store for the backend of the registry. To configure, for example, s3 you can create a YAML or cue file with the config block outlined in the registry documentation.

s3-config.yaml:

```yaml
s3:
  accesskey:                   "${secret://user-secret-data/s3accesskey}"
  secretkey:                   "${secret://user-secret-data/s3secretkey}"
  region:                      "us-west-1"
  bucket:                      "mybucket"
  secure:                      true
  v4auth:                      true
  chunksize:                   5242880
  multipartcopychunksize:      33554432
  multipartcopymaxconcurrency: 100
  multipartcopythresholdsize:  33554432
```

This config blob is using data from the secret `user-secret-data`. This should be populated ahead of time:

`kubectl create secret generic my-data --type opaque --from-literal=s3accesskey=myaccesskey --from-literal=s3secretkey=mysecretkey`

To consume this as part of the deployment run:

```shell
> acorn run -d <fqdn>:registry --secret my-data:user-secret-data acorn-io/library/registry:2.8.1 --storage-config @s3-config.yaml
```

### Configure auth

### Add extra configuration

If you would like to add other configuration options not built in, you can pass configuration at run time.

middleware.yaml

```yaml
middleware:
  repository:
  - name: ARepositoryMiddleware
    options:
    foo: bar
```

Pass this config at run time

`acorn run -d <fqdn>:registry -s my-data:user-secret-data acorn-io/library/registry:2.8.1 --extra-config @middleware.yaml`
