#!/bin/bash
set -x

# Auxiliary functions
function retry_while() {
    local -r cmd="${1:?cmd is missing}"
    local -r retries="${2:-12}"
    local -r sleep_time="${3:-5}"
    local return_value=1

    read -r -a command <<< "$cmd"
    for ((i = 1 ; i <= retries ; i+=1 )); do
        "${command[@]}" && return_value=0 && break
        sleep "$sleep_time"
    done
    return $return_value
}

function get_k8s_svc_lb_ip() {
    local namespace=${1:?namespace is missing}
    local service=${2:?service is missing}
    local service_ip=$(kubectl get svc -l "acorn.io/service-publish=true,acorn.io/service-name=$service" -n "$namespace" -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    local service_hostname=$(kubectl get svc -l "acorn.io/service-publish=true,acorn.io/service-name=$service" -n "$namespace" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")

    if [[ -n ${service_ip} ]]; then
        echo "${service_ip}"
    else
        echo "${service_hostname}"
    fi
}

function is_k8s_svc_lb_ip_ready() {
    local namespace=${1:?namespace is missing}
    local service=${2:?service is missing}
    [[ -n "$(get_k8s_svc_lb_ip "$namespace" "$service")" ]]
}

SHARED_FILE="/tmp/shared/ip.txt"
# Wait until LoadBalancer IP is ready
retry_while "is_k8s_svc_lb_ip_ready $MY_POD_NAMESPACE $MY_POD_NAME" || exit 1
# Obtain LoadBalancer external IP
get_k8s_svc_lb_ip "$MY_POD_NAMESPACE" "$MY_POD_NAME" | tee "$SHARED_FILE"
