#!/bin/bash

set -e

touch ${backup_root_dir}/restore_in_progress

backup_filename=${1}
backup_dir_name="${1%.*}"

backup_root_dir='/backups'
backup_to_restore="${backup_root_dir}/${backup_filename}"

if [ ! -f "${backup_to_restore}" ]; then
	echo "Backup file ${backup_to_restore} not found!"
	exit 1
fi

echo "Untaring backup... ${backup_to_restore}"
tar -zxvf "${backup_to_restore}" -C /scratch/

echo "Preparing backup..."
mariabackup --prepare --target-dir=/scratch/backups/${backup_dir_name}/

echo "Cleaning out old data dir"
rm -rf /var/lib/mysql/*

echo "Restoring..."
mariabackup --copy-back --target-dir=/scratch/backups/${backup_dir_name}/

echo "Cleaning up scratch..."
rm -rf /scratch/*

echo "removing restore lock"
rm ${backup_root_dir}/restore_in_progress

echo "remove backup arg and scale to 1"