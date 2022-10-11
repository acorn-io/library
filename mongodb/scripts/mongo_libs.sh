#!/bin/bash

. /acorn/scripts/common_libs.sh
. /acorn/scripts/env.sh

########################
# Determine the hostname by which to contact the locally running mongo daemon
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   The value of get_machine_ip, $MONGODB_ADVERTISED_HOSTNAME or the current host address
########################
get_mongo_hostname() {
    if is_boolean_yes "$MONGODB_ADVERTISE_IP"; then
        get_machine_ip
    elif [[ -n "$MONGODB_ADVERTISED_HOSTNAME" ]]; then
        echo "$MONGODB_ADVERTISED_HOSTNAME"
    else
        hostname
    fi
}

########################
# Determine the port on which to contact the locally running mongo daemon
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   The value of $MONGODB_ADVERTISED_PORT_NUMBER or $MONGODB_PORT_NUMBER
########################
get_mongo_port() {
    if [[ -n "$MONGODB_ADVERTISED_PORT_NUMBER" ]]; then
        echo "$MONGODB_ADVERTISED_PORT_NUMBER"
    else
        echo "$MONGODB_PORT_NUMBER"
    fi
}

########################
# Stop MongoDB
# Globals:
#   MONGODB_PID_FILE
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_stop() {
    ! is_mongodb_running && return
    info "Stopping MongoDB..."

    stop_service_using_pid "$MONGODB_PID_FILE"
    if ! retry_while "is_mongodb_not_running" "$MONGODB_MAX_TIMEOUT"; then
        error "MongoDB failed to stop"
        exit 1
    fi
}
########################
# Retart MongoDB service
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_restart() {
    mongodb_stop
    mongodb_start_bg "$MONGODB_CONF_FILE"
}

########################
# Execute an arbitrary query/queries against the running MongoDB service
# Stdin:
#   Query/queries to execute
# Arguments:
#   $1 - User to run queries
#   $2 - Password
#   $3 - Database where to run the queries
#   $4 - Host (default to result of get_mongo_hostname function)
#   $5 - Port (default $MONGODB_PORT_NUMBER)
#   $6 - Extra arguments (default $MONGODB_SHELL_EXTRA_FLAGS)
# Returns:
#   output of mongo query
########################
mongodb_execute_print_output() {
    local -r user="${1:-}"
    local -r password="${2:-}"
    local -r database="${3:-}"
    local -r host="${4:-$(get_mongo_hostname)}"
    local -r port="${5:-$MONGODB_PORT_NUMBER}"
    local -r extra_args="${6:-$MONGODB_SHELL_EXTRA_FLAGS}"
    local final_user="$user"
    # If password is empty it means no auth, do not specify user
    [[ -z "$password" ]] && final_user=""

    local -a args=("--host" "$host" "--port" "$port")
    [[ -n "$final_user" ]] && args+=("-u" "$final_user")
    [[ -n "$password" ]] && args+=("-p" "$password")
    if [[ -n "$extra_args" ]]; then
        local extra_args_array=()
        read -r -a extra_args_array <<<"$extra_args"
        [[ "${#extra_args_array[@]}" -gt 0 ]] && args+=("${extra_args_array[@]}")
    fi
    [[ -n "$database" ]] && args+=("$database")

    "$MONGODB_BIN_DIR/mongosh" "${args[@]}"
}

########################
# Get if primary node is initialized
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   None
#########################
mongodb_is_primary_node_initiated() {
    local node="${1:?node is required}"
    local port="${2:?port is required}"
    local result
    result=$(
        mongodb_execute_print_output "$MONGODB_ROOT_USER" "$MONGODB_ROOT_PASSWORD" "admin" "127.0.0.1" "$MONGODB_PORT_NUMBER" <<EOF
rs.initiate({"_id":"$MONGODB_REPLICA_SET_NAME", "members":[{"_id":0,"host":"$node:$port","priority":5}]})
EOF
    )

    # Code 23 is considered OK
    # It indicates that the node is already initialized
    if grep -q "already initialized" <<<"$result"; then
        warn "Node already initialized."
        return 0
    fi

    if ! grep -q "ok: 1" <<<"$result"; then
        warn "Problem initiating replica set
            request: rs.initiate({\"_id\":\"$MONGODB_REPLICA_SET_NAME\", \"members\":[{\"_id\":0,\"host\":\"$node:$port\",\"priority\":5}]})
            response: $result"
        return 1
    fi
}

########################
# Configure primary node
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   None
#########################
mongodb_configure_primary() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    info "Configuring MongoDB primary node"
    # wait-for-port --timeout 360 "$MONGODB_PORT_NUMBER"

    if ! retry_while "mongodb_is_primary_node_initiated $node $port" "$MONGODB_MAX_TIMEOUT"; then
        error "MongoDB primary node failed to get configured"
        exit 1
    fi
}

########################
# Check if a MongoDB node is running
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   Boolean
#########################
mongodb_is_node_available() {
    local -r host="${1:?node is required}"
    local -r port="${2:?port is required}"
    local -r user="${3:?user is required}"
    local -r password="${4:-}"

    local result
    result=$(
        mongodb_execute_print_output "$user" "$password" "admin" "$host" "$port" <<EOF
db.getUsers()
EOF
    )
    if ! grep -q "user:" <<<"$result"; then
        # If no password was provided on first run
        # it may be the case that DB is up but has no users
        [[ -z $password ]] && grep -q "\[\ \]" <<<"$result"
    fi
}

########################
# Wait for node
# Globals:
#   MONGODB_*
# Returns:
#   Boolean
#########################
mongodb_wait_for_node() {
    local -r host="${1:?node is required}"
    local -r port="${2:?port is required}"
    local -r user="${3:?user is required}"
    local -r password="${4:-}"
    debug "Waiting for primary node..."

    info "Trying to connect to MongoDB server $host..."

    if ! retry_while "mongodb_is_node_available $host $port $user $password" "$MONGODB_MAX_TIMEOUT"; then
        error "Node $host did not become available"
        exit 1
    else
        info "MongoDB server listening and working at $host:$port !"
    fi
}

########################
# Check if primary node is ready
# Globals:
#   None
# Returns:
#   None
#########################
mongodb_is_primary_node_up() {
    local -r host="${1:?node is required}"
    local -r port="${2:?port is required}"
    local -r user="${3:?user is required}"
    local -r password="${4:-}"

    debug "Validating $host as primary node..."

    result=$(
        mongodb_execute_print_output "$user" "$password" "admin" "$host" "$port" <<EOF
db.isMaster().ismaster
EOF
    )
    grep -q "true" <<<"$result"
}

########################
# Wait for primary node
# Globals:
#   MONGODB_*
# Returns:
#   Boolean
#########################
mongodb_wait_for_primary_node() {
    local -r host="${1:?node is required}"
    local -r port="${2:?port is required}"
    local -r user="${3:?user is required}"
    local -r password="${4:-}"
    debug "Waiting for primary node..."

    mongodb_wait_for_node "$host" "$port" "$user" "$password"

    debug "Waiting for primary host $host to be ready..."
    if ! retry_while "mongodb_is_primary_node_up $host $port $user $password" "$MONGODB_MAX_TIMEOUT"; then
        error "Unable to validate $host as primary node in the replica set scenario!"
        exit 1
    else
        info "Primary node ready."
    fi
}

########################
# Get current status of the replicaset
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   None
#########################
mongodb_node_currently_in_cluster() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"
    local result

    result=$(
        mongodb_execute "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
rs.status().members
EOF
    )
    grep -q -E "'${node}:${port}'" <<<"$result"
}

########################
# Get if secondary node is pending
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   Boolean
#########################
mongodb_is_secondary_node_pending() {
    local node="${1:?node is required}"
    local port="${2:?port is required}"
    local result

    mongodb_set_dwc

    debug "Adding secondary node ${node}:${port}"
    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
rs.add({host: '$node:$port', priority: 0, votes: 0})
EOF
    )
    debug "$result"

    # Error code 103 is considered OK
    # It indicates a possibly desynced configuration, which will become resynced when the secondary joins the replicaset
    # Note: Error NewReplicaSetConfigurationIncompatible rejects the node addition so we need to filter it out
    if { grep -q "code: 103" <<<"$result"; } && ! { grep -q "NewReplicaSetConfigurationIncompatible" <<<"$result"; }; then
        warn "The ReplicaSet configuration is not aligned with primary node's configuration. Starting secondary node so it syncs with ReplicaSet..."
        return 0
    fi
    grep -q "ok: 1" <<<"$result"
}

########################
# Wait for Confirmation
# Globals:
#   None
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   Boolean
#########################
mongodb_wait_confirmation() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    debug "Waiting until ${node}:${port} is added to the replica set..."
    if ! retry_while "mongodb_node_currently_in_cluster ${node} ${port}" "$MONGODB_MAX_TIMEOUT"; then
        error "Unable to confirm that ${node}:${port} has been added to the replica set!"
        exit 1
    else
        info "Node ${node}:${port} is confirmed!"
    fi
}

########################
# Get if secondary node is ready to be granted voting rights
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   Boolean
#########################
mongodb_is_secondary_node_ready() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    debug "Waiting for the node to be marked as secondary"
    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
rs.status().members.filter(m => m.name === '$node:$port' && m.stateStr === 'SECONDARY').length === 1
EOF
    )
    debug "$result"

    grep -q "true" <<<"$result"
}

########################
# Get MongoDB version
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   version
#########################
mongodb_get_version() {
    mongod --version 2>/dev/null | awk -F\" '/"version"/ {print $4}'
}

########################
# Grant voting rights to secondary node
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   Boolean
#########################
mongodb_configure_secondary_node_voting() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    debug "Granting voting rights to the node"
    local reconfig_cmd="rs.reconfigForPSASet(member, cfg)"
    [[ "$(mongodb_get_version)" =~ ^4\.(0|2)\. ]] && reconfig_cmd="rs.reconfig(cfg)"
    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
cfg = rs.conf()
member = cfg.members.findIndex(m => m.host === '$node:$port')
cfg.members[member].priority = 1
cfg.members[member].votes = 1
$reconfig_cmd
EOF
    )
    debug "$result"

    grep -q "ok: 1" <<<"$result"
}

########################
# Configure secondary node
# Globals:
#   None
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   None
#########################
mongodb_configure_secondary() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    mongodb_wait_for_primary_node "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD"

    if mongodb_node_currently_in_cluster "$node" "$port"; then
        info "Node currently in the cluster"
    else
        info "Adding node to the cluster"
        if ! retry_while "mongodb_is_secondary_node_pending $node $port" "$MONGODB_MAX_TIMEOUT"; then
            error "Secondary node did not get ready"
            exit 1
        fi
        mongodb_wait_confirmation "$node" "$port"

        # Ensure that secondary nodes do not count as voting members until they are fully initialized
        # https://docs.mongodb.com/manual/reference/method/rs.add/#behavior
        if ! retry_while "mongodb_is_secondary_node_ready $node $port" "$MONGODB_MAX_TIMEOUT"; then
            error "Secondary node did not get marked as secondary"
            exit 1
        fi

        # Grant voting rights to node
        # https://docs.mongodb.com/manual/tutorial/modify-psa-replica-set-safely/
        if ! retry_while "mongodb_configure_secondary_node_voting $node $port" "$MONGODB_MAX_TIMEOUT"; then
            error "Secondary node did not get marked as secondary"
            exit 1
        fi

        # Mark node as readable. This is necessary in cases where the PVC is lost
        if is_boolean_yes "$MONGODB_SET_SECONDARY_OK"; then
            mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" <<EOF
rs.secondaryOk()
EOF
        fi

    fi
}

########################
# Set "Default Write Concern"
# https://docs.mongodb.com/manual/reference/command/setDefaultRWConcern/
# Globals:
#   MONGODB_*
# Returns:
#   Boolean
#########################
mongodb_set_dwc() {
    local result

    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
db.adminCommand({"setDefaultRWConcern" : 1, "defaultWriteConcern" : {"w" : "majority"}})
EOF
    )
    if grep -q "ok: 1" <<<"$result"; then
        debug 'Setting Default Write Concern to {"setDefaultRWConcern" : 1, "defaultWriteConcern" : {"w" : "majority"}}'
        return 0
    else
        return 1
    fi
}

########################
# Get if arbiter node is pending
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   Boolean
#########################
mongodb_is_arbiter_node_pending() {
    local node="${1:?node is required}"
    local port="${2:?port is required}"
    local result

    mongodb_set_dwc

    debug "Adding arbiter node ${node}:${port}"
    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
rs.addArb('$node:$port')
EOF
    )
    grep -q "ok: 1" <<<"$result"
}

########################
# Configure arbiter node
# Globals:
#   None
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   None
#########################
mongodb_configure_arbiter() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    mongodb_wait_for_primary_node "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD"

    if mongodb_node_currently_in_cluster "$node" "$port"; then
        info "Node currently in the cluster"
    else
        info "Configuring MongoDB arbiter node"
        if ! retry_while "mongodb_is_arbiter_node_pending $node $port" "$MONGODB_MAX_TIMEOUT"; then
            error "Arbiter node did not get ready"
            exit 1
        fi
        mongodb_wait_confirmation "$node" "$port"
    fi
}

########################
# Get if hidden node is pending
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   Boolean
#########################
mongodb_is_hidden_node_pending() {
    local node="${1:?node is required}"
    local port="${2:?port is required}"
    local result

    mongodb_set_dwc

    debug "Adding hidden node ${node}:${port}"
    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
rs.add({host: '$node:$port', hidden: true, priority: 0})
EOF
    )
    # Error code 103 is considered OK.
    # It indicates a possiblely desynced configuration,
    # which will become resynced when the hidden joins the replicaset.
    if grep -q "code: 103" <<<"$result"; then
        warn "The ReplicaSet configuration is not aligned with primary node's configuration. Starting hidden node so it syncs with ReplicaSet..."
        return 0
    fi
    grep -q "ok: 1" <<<"$result"
}

########################
# Configure hidden node
# Globals:
#   None
# Arguments:
#   $1 - node
#   $2 - port
# Returns:
#   None
#########################
mongodb_configure_hidden() {
    local -r node="${1:?node is required}"
    local -r port="${2:?port is required}"

    mongodb_wait_for_primary_node "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD"

    if mongodb_node_currently_in_cluster "$node" "$port"; then
        info "Node currently in the cluster"
    else
        info "Adding hidden node to the cluster"
        if ! retry_while "mongodb_is_hidden_node_pending $node $port" "$MONGODB_MAX_TIMEOUT"; then
            error "Hidden node did not get ready"
            exit 1
        fi
        mongodb_wait_confirmation "$node" "$port"
    fi
}

########################
# Get if the replica set in synced
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_is_not_in_sync() {
    local result

    result=$(
        mongodb_execute_print_output "$MONGODB_INITIAL_PRIMARY_ROOT_USER" "$MONGODB_INITIAL_PRIMARY_ROOT_PASSWORD" "admin" "$MONGODB_INITIAL_PRIMARY_HOST" "$MONGODB_INITIAL_PRIMARY_PORT_NUMBER" <<EOF
db.printSecondaryReplicationInfo()
EOF
    )

    grep -q -E "'0 secs" <<<"$result"
}

########################
# Wait until initial data sync complete
# Globals:
#   MONGODB_MAX_TIMEOUT
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_wait_until_sync_complete() {
    info "Waiting until initial data sync is complete..."

    if ! retry_while "mongodb_is_not_in_sync" "$MONGODB_MAX_TIMEOUT" 1; then
        error "Initial data sync did not finish after $MONGODB_MAX_TIMEOUT seconds"
        exit 1
    else
        info "initial data sync completed"
    fi
}

########################
# Configure Replica Set
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_configure_replica_set() {
    local node
    local port

    info "Configuring MongoDB replica set..."

    node=$(get_mongo_hostname)
    port=$(get_mongo_port)
    mongodb_restart

    case "$MONGODB_REPLICA_SET_MODE" in
    "primary")
        mongodb_configure_primary "$node" "$port"
        ;;
    "secondary")
        mongodb_configure_secondary "$node" "$port"
        ;;
    "arbiter")
        mongodb_configure_arbiter "$node" "$port"
        ;;
    "hidden")
        mongodb_configure_hidden "$node" "$port"
        ;;
    "dynamic")
        # Do nothing
        ;;
    esac

    if [[ "$MONGODB_REPLICA_SET_MODE" = "secondary" ]]; then
        mongodb_wait_until_sync_complete
    fi
}

########################
# Apply regex in MongoDB configuration file
# Globals:
#   MONGODB_CONF_FILE
# Arguments:
#   $1 - match regex
#   $2 - substitute regex
# Returns:
#   None
#########################
mongodb_config_apply_regex() {
    local -r match_regex="${1:?match_regex is required}"
    local -r substitute_regex="${2:?substitute_regex is required}"
    local -r conf_file_path="${3:-$MONGODB_CONF_FILE}"
    local mongodb_conf

    mongodb_conf="$(sed -E "s@$match_regex@$substitute_regex@" "$conf_file_path")"
    echo "$mongodb_conf" >"$conf_file_path"
}

########################
# Check if a given file was mounted externally
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - Filename
# Returns:
#   true if the file was mounted externally, false otherwise
#########################
mongodb_is_file_external() {
    local -r filename="${1:?file_is_missing}"
    if [[ -f "${MONGODB_MOUNTED_CONF_DIR}/${filename}" ]] || { [[ -f "${MONGODB_CONF_DIR}/${filename}" ]] && ! test -w "${MONGODB_CONF_DIR}/${filename}"; }; then
        true
    else
        false
    fi
}

########################
# Change bind ip address to 0.0.0.0
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_set_listen_all_conf() {
    local -r conf_file_path="${1:-$MONGODB_CONF_FILE}"
    local -r conf_file_name="${conf_file_path#"$MONGODB_CONF_DIR"}"

    mongodb_config_apply_regex "#?bindIp:.*" "#bindIp:" "$conf_file_path"
    mongodb_config_apply_regex "#?bindIpAll:.*" "bindIpAll: true" "$conf_file_path"
}

########################
# Enable ReplicaSetMode
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_set_replicasetmode_conf() {
    local -r conf_file_path="${1:-$MONGODB_CONF_FILE}"
    local -r conf_file_name="${conf_file_path#"$MONGODB_CONF_DIR"}"
    mongodb_config_apply_regex "#?replication:.*" "replication:" "$conf_file_path"
    mongodb_config_apply_regex "#?replSetName:" "replSetName:" "$conf_file_path"
    mongodb_config_apply_regex "#?enableMajorityReadConcern:.*" "enableMajorityReadConcern:" "$conf_file_path"
    if [[ -n "$MONGODB_REPLICA_SET_NAME" ]]; then
        mongodb_config_apply_regex "replSetName:.*" "replSetName: $MONGODB_REPLICA_SET_NAME" "$conf_file_path"
    fi
    if [[ -n "$MONGODB_ENABLE_MAJORITY_READ" ]]; then
        mongodb_config_apply_regex "enableMajorityReadConcern:.*" "enableMajorityReadConcern: $({ (is_boolean_yes "$MONGODB_ENABLE_MAJORITY_READ" || [[ "$(mongodb_get_version)" =~ ^5\..\. ]]) && echo 'true'; } || echo 'false')" "$conf_file_path"
    fi
}

########################
# Set the path to the keyfile in mongodb.conf
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_set_keyfile_conf() {
    local -r conf_file_path="${1:-$MONGODB_CONF_FILE}"
    local -r conf_file_name="${conf_file_path#"$MONGODB_CONF_DIR"}"

    mongodb_config_apply_regex "#?keyFile:.*" "keyFile: $MONGODB_KEY_FILE" "$conf_file_path"
}

########################
# Change common network settings
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_set_net_conf() {
    local -r conf_file_path="${1:-$MONGODB_CONF_FILE}"
    local -r conf_file_name="${conf_file_path#"$MONGODB_CONF_DIR"}"

    if [[ -n "$MONGODB_PORT_NUMBER" ]]; then
        mongodb_config_apply_regex "port:.*" "port: $MONGODB_PORT_NUMBER" "$conf_file_path"
    fi
}

########################
# Check if mongo is accepting requests
# Globals:
#   MONGODB_DATABASE and MONGODB_EXTRA_DATABASES
# Arguments:
#   None
# Returns:
#   Boolean
#########################
mongodb_is_mongodb_started() {
    local result

    result=$(
        mongodb_execute_print_output <<EOF
db
EOF
    )
    [[ -n "$result" ]]
}

########################
# Check if MongoDB is running
# Globals:
#   MONGODB_PID_FILE
# Arguments:
#   None
# Returns:
#   Boolean
#########################
is_mongodb_running() {
    local pid
    pid="$(get_pid_from_file "$MONGODB_PID_FILE")"

    if [[ -z "$pid" ]]; then
        false
    else
        is_service_running "$pid"
    fi
}

########################
# Check if MongoDB is not running
# Globals:
#   MONGODB_PID_FILE
# Arguments:
#   None
# Returns:
#   Boolean
#########################
is_mongodb_not_running() {
    ! is_mongodb_running
    return "$?"
}

########################
# Start MongoDB server in the background and waits until it's ready
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - Path to MongoDB configuration file
# Returns:
#   None
#########################
mongodb_start_bg() {
    # Use '--fork' option to enable daemon mode
    # ref: https://docs.mongodb.com/manual/reference/program/mongod/#cmdoption-mongod-fork
    local -r conf_file="${1:-$MONGODB_CONF_FILE}"
    local flags=("--fork" "--config=$conf_file")
    if [[ -n "${MONGODB_EXTRA_FLAGS:-}" ]]; then
        local extra_flags_array=()
        read -r -a extra_flags_array <<<"$MONGODB_EXTRA_FLAGS"
        [[ "${#extra_flags_array[@]}" -gt 0 ]] && flags+=("${extra_flags_array[@]}")
    fi

    debug "Starting MongoDB in background..."

    is_mongodb_running && return

    if am_i_root; then
        debug "${flags[@]}"
        gosu "$MONGODB_DAEMON_USER" "$MONGODB_BIN_DIR/mongod" "${flags[@]}"
    else
        "$MONGODB_BIN_DIR/mongod" "${flags[@]}"
    fi

    # wait until the server is up and answering queries
    if ! retry_while "mongodb_is_mongodb_started" "$MONGODB_MAX_TIMEOUT"; then
        error "MongoDB did not start"
        exit 1
    fi
}

########################
# Execute an arbitrary query/queries against the running MongoDB service
# Stdin:
#   Query/queries to execute
# Arguments:
#   $1 - User to run queries
#   $2 - Password
#   $3 - Database where to run the queries
#   $4 - Host (default to result of get_mongo_hostname function)
#   $5 - Port (default $MONGODB_PORT_NUMBER)
#   $6 - Extra arguments (default $MONGODB_SHELL_EXTRA_FLAGS)
# Returns:
#   None
########################
mongodb_execute() {
    local -r user="${1:-}"
    local -r password="${2:-}"
    local -r database="${3:-}"
    local -r host="${4:-$(get_mongo_hostname)}"
    local -r port="${5:-$MONGODB_PORT_NUMBER}"
    local -r extra_args="${6:-$MONGODB_SHELL_EXTRA_FLAGS}"
    local final_user="$user"
    # If password is empty it means no auth, do not specify user
    [[ -z "$password" ]] && final_user=""

    local -a args=("--host" "$host" "--port" "$port")
    [[ -n "$final_user" ]] && args+=("-u" "$final_user")
    [[ -n "$password" ]] && args+=("-p" "$password")
    if [[ -n "$extra_args" ]]; then
        local extra_args_array=()
        read -r -a extra_args_array <<<"$extra_args"
        [[ "${#extra_args_array[@]}" -gt 0 ]] && args+=("${extra_args_array[@]}")
    fi
    [[ -n "$database" ]] && args+=("$database")

    "mongosh" "${args[@]}"
}

########################
# Create a MongoDB user and provide read/write permissions on a database
# Globals:
#   MONGODB_ROOT_PASSWORD
# Arguments:
#   $1 - Name of user
#   $2 - Password for user
#   $3 - Name of database (empty for default database)
# Returns:
#   None
#########################
mongodb_create_user() {
    local -r user="${1:?user is required}"
    local -r password="${2:-}"
    local -r database="${3:-}"
    local query

    if [[ -z "$password" ]]; then
        warn "Cannot create user '$user', no password provided"
        return 0
    fi
    # Build proper query (default database or specific one)
    query="db.getSiblingDB('$database').createUser({ user: '$user', pwd: '$password', roles: [{role: 'readWrite', db: '$database'}] })"
    [[ -z "$database" ]] && query="db.getSiblingDB(db.stats().db).createUser({ user: '$user', pwd: '$password', roles: [{role: 'readWrite', db: db.getSiblingDB(db.stats().db).stats().db }] })"
    # Create user, discarding mongo CLI output for clean logs
    info "Creating user '$user'..."
    mongodb_execute "$MONGODB_ROOT_USER" "$MONGODB_ROOT_PASSWORD" "" "127.0.0.1" <<<"$query"
}

########################
# Create the appropriate users
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_create_users() {
    info "Creating users..."

    if [[ -n "$MONGODB_ROOT_PASSWORD" ]] && ! [[ "$MONGODB_REPLICA_SET_MODE" =~ ^(secondary|arbiter|hidden) ]]; then
        info "Creating $MONGODB_ROOT_USER user..."
        mongodb_execute "" "" "" "127.0.0.1" <<EOF
db.getSiblingDB('admin').createUser({ user: '$MONGODB_ROOT_USER', pwd: '$MONGODB_ROOT_PASSWORD', roles: [{role: 'root', db: 'admin'}] })
EOF
    fi

    if [[ -n "$MONGODB_USERNAME" ]]; then
        mongodb_create_user "$MONGODB_USERNAME" "$MONGODB_PASSWORD" "$MONGODB_DATABASE"
    fi

    info "Users created"
}

########################
# Create the replica set key file
# Globals:
#   MONGODB_*
# Arguments:
#   $1 - key
# Returns:
#   None
#########################
mongodb_create_keyfile() {
    local -r key="${1:?key is required}"

    info "Writing keyfile for replica set authentication..."
    echo "$key" >"$MONGODB_KEY_FILE"

    chmod 600 "$MONGODB_KEY_FILE"

    if am_i_root; then
        find -L "$MONGODB_KEY_FILE" -type f -exec chmod "600" {} \;
        chown -LR "$MONGODB_DAEMON_USER":"$MONGODB_DAEMON_GROUP" "$MONGODB_KEY_FILE"
    else
        chmod 600 "$MONGODB_KEY_FILE"
    fi
}

########################
# Enable Auth
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Return
#   None
#########################
mongodb_set_auth_conf() {
    local -r conf_file_path="${1:-$MONGODB_CONF_FILE}"
    local -r conf_file_name="${conf_file_path#"$MONGODB_CONF_DIR"}"

    if [[ -n "$MONGODB_ROOT_PASSWORD" ]] || [[ -n "$MONGODB_PASSWORD" ]]; then
        # removed yq operations
        info "Enabling authentication..."
        mongodb_config_apply_regex "#?authorization:.*" "authorization: enabled" "$conf_file_path"
        mongodb_config_apply_regex "#?enableLocalhostAuthBypass:.*" "enableLocalhostAuthBypass: false" "$conf_file_path"
    fi
}

########################
# Copy mounted configuration files
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_copy_mounted_config() {
    if ! is_dir_empty "$MONGODB_MOUNTED_CONF_DIR"; then
        if ! cp -Lr "$MONGODB_MOUNTED_CONF_DIR"/* "$MONGODB_CONF_DIR"; then
            error "Issue copying mounted configuration files from $MONGODB_MOUNTED_CONF_DIR to $MONGODB_CONF_DIR. Make sure you are not mounting configuration files in $MONGODB_CONF_DIR and $MONGODB_MOUNTED_CONF_DIR at the same time"
            exit 1
        fi
    fi
}

########################
# Drop local Database
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_drop_local_database() {
    info "Dropping local database to reset replica set setup..."
    local command=("mongodb_execute")

    if [[ -n "$MONGODB_USERNAME" ]]; then
        command=("${command[@]}" "$MONGODB_USERNAME" "$MONGODB_PASSWORD")
    fi
    "${command[@]}" <<EOF
db.getSiblingDB('local').dropDatabase()
EOF
}

########################
# Check that the dynamic instance configuration is consistent
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_ensure_dynamic_mode_consistency() {
    if grep -q -E "^[[:space:]]*replSetName: $MONGODB_REPLICA_SET_NAME" "$MONGODB_CONF_FILE"; then
        info "ReplicaSetMode set to \"dynamic\" and replSetName different from config file."
        info "Dropping local database ..."
        mongodb_start_bg "$MONGODB_CONF_FILE"
        mongodb_drop_local_database
        mongodb_stop
    fi
}

###############
# Initialize MongoDB service
# Globals:
#   MONGODB_*
# Arguments:
#   None
# Returns:
#   None
#########################
mongodb_initialize() {
    info "Initializing MongoDB..."

    rm -f "$MONGODB_PID_FILE"
    mongodb_copy_mounted_config
    mongodb_set_net_conf "$MONGODB_CONF_FILE"

    if is_dir_empty "$MONGODB_DATA_DIR/db"; then
        info "Deploying MongoDB from scratch..."
        ensure_dir_exists "$MONGODB_DATA_DIR/db"
        am_i_root && chown -R "$MONGODB_DAEMON_USER" "$MONGODB_DATA_DIR/db"

        mongodb_start_bg "$MONGODB_CONF_FILE"
        mongodb_create_users
        if [[ -n "$MONGODB_REPLICA_SET_MODE" ]]; then
            if [[ -n "$MONGODB_REPLICA_SET_KEY" ]]; then
                mongodb_create_keyfile "$MONGODB_REPLICA_SET_KEY"
                mongodb_set_keyfile_conf "$MONGODB_CONF_FILE"
            fi
            mongodb_set_replicasetmode_conf "$MONGODB_CONF_FILE"
            mongodb_set_listen_all_conf "$MONGODB_CONF_FILE"
            mongodb_configure_replica_set
        fi

        mongodb_stop
    else
        mongodb_set_auth_conf "$MONGODB_CONF_FILE"
        info "Deploying MongoDB with persisted data..."
        if [[ -n "$MONGODB_REPLICA_SET_MODE" ]]; then
            if [[ -n "$MONGODB_REPLICA_SET_KEY" ]]; then
                mongodb_create_keyfile "$MONGODB_REPLICA_SET_KEY"
                mongodb_set_keyfile_conf "$MONGODB_CONF_FILE"
            fi
            if [[ "$MONGODB_REPLICA_SET_MODE" = "dynamic" ]]; then
                mongodb_ensure_dynamic_mode_consistency
            fi
            mongodb_set_replicasetmode_conf "$MONGODB_CONF_FILE"
        fi
    fi

    mongodb_set_auth_conf "$MONGODB_CONF_FILE"
}

