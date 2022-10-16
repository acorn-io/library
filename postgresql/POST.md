# Writing Acorn files


## All-in-one experience

After creating the Acorn package for highly available (HA) PostgreSQL I have found a lot of interesting and useful features for dockerized applications developers. In general, I have found Acorn as an effective tool for docker based application deployments to Kubernetes clusters. It is cofortable to manage both for local application development (e.g. with Minikube) and either with managed clusters like EKS, AKS or GKE. 

### Docker compose for Kubernetes

In two words Acorn file could be considered as a docker-compose file for deploying application into Kubernetes cluster (instead of local Docker utilization).

### Scripting language

The other powerfull feature is built-in scripting language which could be used in Acorn files. 


## Secrets management

Secret management is a quite often problem in containerized applications development.

### Different secret types

The concept of secrets includes a few of separate secrets types, which could be used in different ways.

### Password autogeneration

Simple but powerful function is password auto generation. It gives the possibility to generate passwords on the fly (and do not pay a lot of attention for secured storage).

## Disk mounts

Mounted disks are useful and often used for persistent data storage creation. But also it could be used for mounting initialisation and service scripts.

### Service scripts

It is useful for database Acorn implementations, because RDBMS should usually support such features like dunping and restoring backups.

### SQL init

Sometimes, databases require initial SQL queries to be executed.

## Some issues for the further improvements

### Ingress controllers

### User context