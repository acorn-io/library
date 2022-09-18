#!/bin/bash

set -e

backup_host=${1}

backup_root_dir='/backup'
ts=`date +"%Y%m%d-%H%M%S"`
backup_dir_name="postgres-backup-${ts}"
this_backup_dir="${backup_root_dir}/${backup_dir_name}"

mkdir -p ${this_backup_dir}

PGPASSWORD=${POSTGRES_PASSWORD} pg_dump -h postgresql ${POSTGRES_DB} -U ${POSTGRES_USER} > "${this_backup_dir}/dump.sql"
	
cd ${backup_root_dir}
tar -zcvf ${backup_dir_name}.tgz ${this_backup_dir} && rm -rf ${this_backup_dir}