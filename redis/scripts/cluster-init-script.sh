#!/bin/sh

set -e

leader_server_count=${1}
replica_count=${2}
total_server_count=${3}


leader_server_count_idx=$(expr ${leader_server_count} - 1)
replica_count_idx=0
if [ "${replica_count}" -gt 0 ]; then
  replica_count_idx=$(expr ${replica_count} - 1)
fi

cluster_init_script=/acorn/scripts/redis-cluster-init.sh

# wait until services become available
for l in $(seq 0 ${leader_server_count_idx}); do
  for f in $(seq 0 ${replica_count_idx}); do
    echo "checking redis-${l}-${f}"
  	until timeout -s 3 5 redis-cli -h redis-${l}-${f} -p 6379 ping; do echo "waiting...";sleep 5;done
  done
done

known_nodes=$(redis-cli -h redis-0-0 cluster info |grep cluster_known_nodes|tr -d '[:space:]'|cut -d: -f2)
cluster_size=$(redis-cli -h redis-0-0 cluster info |grep cluster_size|tr -d '[:space:]'|cut -d: -f2)
if [ "${cluster_size}" -eq "0" ]; then
  echo "initializing cluster..."

  node_string=
  for l in $(seq 0 ${leader_server_count_idx});do
    for f in $(seq 0 ${replica_count});do 
      node_string="${node_string} redis-${l}-${f}:6379 "
    done
  done

  echo "yes" | redis-cli --cluster create ${node_string} --cluster-replicas ${replica_count}

  # Exit because we just setup the cluster and there is nothing else to do
  # in this run of the code.
  echo "Cluster initialized..."
  exit 0
fi

echo "Cluster already initialized..."
if [ "$(redis-cli -h redis-0-0 cluster info |grep cluster_state|tr -d '[:space:]'|cut -d: -f2)" == "fail" ]; then
  echo "Cluster in failed state exiting out"
  exit 1
fi

if [ "${total_server_count}" -eq "${known_nodes}" ] && [ "${leader_server_count}" -eq "${cluster_size}" ]; then
	echo "Scale is set... exiting"
	exit 0
fi

server_diff=$(expr ${total_server_count} - ${known_nodes})
if [ "${server_diff}" -lt "0" ]; then
  echo "this is a scale down event.. manual intervention required"
  exit 0
fi

offset=$(expr ${cluster_size} - 0)
for l in $(seq ${offset} $(expr ${leader_server_count} - 1)); do
   for f in $(seq 0 ${replica_count}); do
     if [ "${f}" -ne "0" ];then
	 	m_id=$(redis-cli -h redis-${l}-0 cluster nodes|grep myself|awk '{print $1}')
	 	replication_flag="--cluster-slave --cluster-master-id ${m_id}"
	 fi
	 redis-cli --cluster add-node redis-${l}-${f}:6379 redis-0-0:6379 ${replication_flag}
	 sleep 5
	 replication_flag=
   done
done
# Let cluster quisce for a few seconds
sleep 5
redis-cli --cluster rebalance redis-0-0:6379 --cluster-use-empty-masters
