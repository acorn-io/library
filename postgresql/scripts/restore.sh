#!/bin/bash

set -e

backup_filename=${1}
#backup_dir_name="${1%.*}"

backup_root_dir='/backups'
backup_to_restore="${backup_root_dir}/${backup_filename}"

#touch ${backup_root_dir}/restore_in_progress

if [ ! -f "${backup_to_restore}" ]; then
	echo "Backup file ${backup_to_restore} not found!"
	exit 1
fi

echo "Untaring backup... ${backup_to_restore}"
tar -zxvf "${backup_to_restore}" -C /scratch/

#echo "Restoring..."
#psql --set ON_ERROR_STOP=on dbname < dumpfile

#echo "Cleaning up scratch..."
rm -rf /scratch/*

#echo "remove backup arg and scale to 1"