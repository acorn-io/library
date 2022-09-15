#!/bin/bash

set -e

backup_host=${1}

backup_root_dir='/backups'
ts=`date +"%Y%m%d-%H%M%S"`
backup_dir_name="mariadb-backup-${ts}"
this_backup_dir="${backup_root_dir}/${backup_dir_name}"

if [ -f "${backup_root_dir}/restore_in_progress" ]; then
   echo "Restore in progress... exiting"
   exit 0
fi

mkdir -p ${this_backup_dir}

/usr/bin/mariabackup --backup --target-dir=${this_backup_dir} \
	--user=${MARIADB_BACKUP_USER} --password=${MARIADB_BACKUP_PASSWORD} \
	--host=${backup_host}

cd ${backup_root_dir}
tar -zcvf ${backup_dir_name}.tgz ${this_backup_dir} && rm -rf ${this_backup_dir}

ls -lrt ${backup_root_dir}/ > /run/secrets/output