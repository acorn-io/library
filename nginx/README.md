# NGINX Acorn

---
This Acorn will deploy NGINX and allows for a lot of customizations.

## How to use this Acorn

### Pre-req

### Quick start

`acorn run [IMAGE] --git-repo https://github.com/my-space/public-content`

This will clone content from this site into the HTML root directory and serve it up.

To expose this service via ingress:

`acorn run -d my-app.example.com:nginx [IMAGE] --git-repo ...`

### Available options

```shell
Volumes:   <none>
Secrets:   nginx-conf, nginx-server-blocks, git-clone-ssh-keys
Container: nginx
Ports:     nginx:80/http

      --git-branch string
      --git-repo string
      --replicas int
```

## Advanced Usage

### Configure custom server blocks

Create a custom secret with the keys equal to the name of the file to place in `/etc/nginx/conf.d/`
The content should be a base64 encoded nginx server block.

When running the acorn:

`acorn run -s my-server-blocks:nginx-server-blocks [IMAGE] ...`

### Configure base configuration

Create a custom secret with that has a data key `template` with the full content of the nginx.conf file to be used.

When running the acorn pass in the secret name:

`acorn run -s my-nginx-conf:nginx-conf [IMAGE] ...`

### Private Checkouts with SSH keys

Create a secret with the ssh keys to use. The keys must already be trusted by the remote repository. You can create the secret like:

`kubectl create secret -n acorn-redis generic my-ssh-keys --from-file=/Users/me/.ssh/id_rsa`

when you run the acorn bind in the secret:
