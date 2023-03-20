# Writing Acorn files


## 1. All-in-one experience

After creating the Acorn package for highly available (HA) PostgreSQL I have found a lot of interesting and useful features for dockerized applications developers. In general, I have found Acorn as an effective tool for docker based application deployments to Kubernetes clusters. It is cofortable to manage both for local application development (e.g. with Minikube) and either with managed clusters like EKS, AKS or GKE. 

### Docker compose for Kubernetes

In two words Acorn file could be considered as a docker-compose file for deploying application into Kubernetes cluster (instead of local Docker utilization). It is quite easy to prepare fast installation package to deliver docker application to Kubernetes cluster and manage it with own CLI tool, like for example: 

                $ acorn app
                  NAME          IMAGE          HEALTHY   UP-TO-DATE   CREATED 
                  rough-field   3435258ee811   3/3       3            12d ago               

### Scripting language

The other powerfull feature is built-in scripting language which could be used in Acorn files. For example, in cycles and for variables.

                for i in std.range(args.replicas)


## 2. Secrets management

Secret management is a quite often difficulity in containerized applications development. Acorn gives the special entity for secrets management and also it is supported by Acorn CLI like the following:

                $ acorn secrets
                ALIAS                                  NAME                        TYPE       KEYS                  CREATED
                rough-field.postgresmaster-conf        postgresmaster-conf-x6w7x   template   [template]            12d ago
                rough-field.root-credentials           root-credentials-nmq2b      basic      [password username]   12d ago

Simple but powerful function is password auto generation. It gives the possibility to generate passwords on the fly (and do not pay a lot of attention for the secured storage). After generation it could be easily revealed with the following example command:

                $ acorn secret expose rough-field.root-credentials
                NAME                     TYPE      KEY        VALUE
                root-credentials-nmq2b   basic     password   gzlxcfg8hx4cbpw6
                root-credentials-nmq2b   basic     username   admin

## 3. Disk mounts

Mounted disks are useful and often used for persistent data storage creation. But also it could be used for mounting initialisation and service scripts. For example:

                volumes: {
	                "backup": {}
                }

Also, separate local folder directories could be mapped as system path. For example, scripts from the folder __scripts__ could be mounted as follows:

                dirs: {
		        "/acorn/scripts": "./scripts"
		        "/backup": "volume://backup"
		}

## 4. Some issues for the further improvements

Acorn is the new technology and there are some challenges could be faced.

### Ingress controllers

If your application requires ingress controllers, then additional steps should be done. Otherwise the following error could be met:

        $ acorn check
          NAME                  PASSED    MESSAGE
          IngressCapability     false     Ingress not ready (test timed out)

Usually it is related with default ingress class. It could be added as a notation to the ingressClass:

        ingressclass.kubernetes.io/is-default-class: „true“

### User context

Some issues could be faced if Docker container uses user context (for example UID: 1001). If this or another issue is met then the best way to resolve it is to ask your question in Acorn slack channel. Acorn has good community support and can provide you with actual solution.  