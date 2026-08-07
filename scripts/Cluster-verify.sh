#!/usr/bin/env bash

# ============================================================
# Kubernetes Cluster Verification Script
# Teleport Take-Home Exercise
#
# Verifies:
#   - Kubernetes API connectivity
#   - Cluster nodes
#   - Node IP addresses
#   - System pods
#   - Flannel networking
#   - Flannel interface selection
#   - CoreDNS
#   - ingress-nginx
#   - ingress admission webhook
#   - cert-manager
#   - Application namespace
#   - NGINX deployment
#   - NGINX service/endpoints
#   - NGINX ingress
#   - HTTP/HTTPS ingress connectivity
#   - Certificate-based user authentication
#   - Namespace-scoped RBAC
#   - Least privilege
#   - CSR state when present
#   - Role / RoleBinding discovery
#   - ClusterRoleBinding safety
#   - Certificate resources
# ============================================================

set -u

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

APP_NAMESPACE="nginx-demo"
APP_NAME="nginx"

RBAC_USER="nginx-user"
RBAC_KUBECONFIG="${RBAC_KUBECONFIG:-nginx-user.conf}"

EXPECTED_CONTROLPLANE_IP="192.168.56.10"
EXPECTED_NODE01_IP="192.168.56.11"
EXPECTED_NODE02_IP="192.168.56.12"

EXPECTED_FLANNEL_INTERFACE="eth1"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# ------------------------------------------------------------
# Formatting Functions
# ------------------------------------------------------------

header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

subheader() {
    echo
    echo -e "${CYAN}--- $1 ---${NC}"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# ------------------------------------------------------------
# Intro
# ------------------------------------------------------------

clear

echo
echo -e "${BOLD}Kubernetes Cluster Validation${NC}"
echo "Teleport Professional Services Take-Home"
echo
echo "Date: $(date)"
echo "Host: $(hostname)"
echo "Application Namespace: $APP_NAMESPACE"
echo "Application: $APP_NAME"
echo "RBAC User: $RBAC_USER"

# ------------------------------------------------------------
# 1. Kubernetes API
# ------------------------------------------------------------

header "1. Kubernetes API"

if kubectl cluster-info >/dev/null 2>&1; then

    pass "Kubernetes API server is reachable."

else

    fail "Unable to communicate with the Kubernetes API server."

    echo
    echo "Check your admin kubeconfig:"
    echo
    echo "  export KUBECONFIG=\$HOME/.kube/config"
    echo

    exit 1
fi

# ------------------------------------------------------------
# 2. Kubernetes Nodes
# ------------------------------------------------------------

header "2. Kubernetes Nodes"

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [[ "$NODE_COUNT" -eq 3 ]]; then

    pass "Expected 3 Kubernetes nodes found."

else

    fail "Expected 3 Kubernetes nodes but found $NODE_COUNT."

fi

echo
kubectl get nodes -o wide

subheader "Node Ready Status"

while read -r NODE STATUS; do

    if [[ "$STATUS" == "Ready" ]]; then
        pass "$NODE is Ready."
    else
        fail "$NODE status is $STATUS."
    fi

done < <(
    kubectl get nodes \
        -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status' \
        --no-headers |
    awk '{
        if ($2=="True")
            print $1,"Ready";
        else
            print $1,"NotReady"
    }'
)

# ------------------------------------------------------------
# 3. Node IP Configuration
# ------------------------------------------------------------

header "3. Node IP Configuration"

check_node_ip() {

    NODE="$1"
    EXPECTED="$2"

    ACTUAL=$(kubectl get node "$NODE" \
        -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' \
        2>/dev/null || true)

    if [[ "$ACTUAL" == "$EXPECTED" ]]; then

        pass "$NODE InternalIP = $ACTUAL"

    else

        fail "$NODE InternalIP is '$ACTUAL'; expected '$EXPECTED'."

    fi
}

check_node_ip "controlplane" "$EXPECTED_CONTROLPLANE_IP"
check_node_ip "node01" "$EXPECTED_NODE01_IP"
check_node_ip "node02" "$EXPECTED_NODE02_IP"

# ------------------------------------------------------------
# 4. Kubernetes System Pods
# ------------------------------------------------------------

header "4. Kubernetes System Pods"

SYSTEM_BAD=$(kubectl get pods \
    -n kube-system \
    --no-headers \
    2>/dev/null |
    awk '$3 != "Running" && $3 != "Completed" {print}')

if [[ -z "$SYSTEM_BAD" ]]; then

    pass "All kube-system pods are healthy."

else

    fail "One or more kube-system pods are unhealthy."
    echo
    echo "$SYSTEM_BAD"

fi

echo
kubectl get pods -n kube-system -o wide

# ------------------------------------------------------------
# 5. Flannel CNI
# ------------------------------------------------------------

header "5. Flannel CNI"

FLANNEL_COUNT=$(kubectl get pods \
    -n kube-flannel \
    -l app=flannel \
    --field-selector=status.phase=Running \
    --no-headers \
    2>/dev/null |
    wc -l |
    tr -d ' ')

if [[ "$FLANNEL_COUNT" -eq 3 ]]; then

    pass "Flannel is running on all 3 nodes."

else

    fail "Expected 3 running Flannel pods; found $FLANNEL_COUNT."

fi

echo
kubectl get pods -n kube-flannel -o wide 2>/dev/null || true

subheader "Flannel Public IPs"

kubectl get nodes \
    -o custom-columns='NODE:.metadata.name,FLANNEL-PUBLIC-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'

echo

EXPECTED_FLANNEL_IPS=(
    "controlplane:192.168.56.10"
    "node01:192.168.56.11"
    "node02:192.168.56.12"
)

for ENTRY in "${EXPECTED_FLANNEL_IPS[@]}"; do

    NODE="${ENTRY%%:*}"
    EXPECTED="${ENTRY##*:}"

    ACTUAL=$(kubectl get node "$NODE" \
        -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip}' \
        2>/dev/null || true)

    if [[ "$ACTUAL" == "$EXPECTED" ]]; then

        pass "Flannel $NODE = $ACTUAL"

    elif [[ "$ACTUAL" == "10.0.2.15" ]]; then

        fail "Flannel on $NODE is incorrectly using VirtualBox NAT IP 10.0.2.15."

    else

        fail "Flannel on $NODE is using '$ACTUAL'; expected '$EXPECTED'."

    fi

done

subheader "Flannel Interface"

FLANNEL_ARGS=$(kubectl get daemonset kube-flannel-ds \
    -n kube-flannel \
    -o jsonpath='{.spec.template.spec.containers[0].args}' \
    2>/dev/null || true)

if [[ "$FLANNEL_ARGS" == *"--iface=${EXPECTED_FLANNEL_INTERFACE}"* ]]; then

    pass "Flannel is configured to use Vagrant private interface $EXPECTED_FLANNEL_INTERFACE."

else

    warn "Flannel does not explicitly contain --iface=$EXPECTED_FLANNEL_INTERFACE."

fi

# ------------------------------------------------------------
# 6. CoreDNS
# ------------------------------------------------------------

header "6. CoreDNS"

DNS_READY=$(kubectl get deployment coredns \
    -n kube-system \
    -o jsonpath='{.status.readyReplicas}' \
    2>/dev/null || echo 0)

DNS_DESIRED=$(kubectl get deployment coredns \
    -n kube-system \
    -o jsonpath='{.spec.replicas}' \
    2>/dev/null || echo 0)

DNS_READY="${DNS_READY:-0}"
DNS_DESIRED="${DNS_DESIRED:-0}"

if [[ "$DNS_READY" == "$DNS_DESIRED" && "$DNS_READY" != "0" ]]; then

    pass "CoreDNS is healthy ($DNS_READY/$DNS_DESIRED replicas)."

else

    fail "CoreDNS is not fully available ($DNS_READY/$DNS_DESIRED replicas)."

fi

# ------------------------------------------------------------
# 7. ingress-nginx
# ------------------------------------------------------------

header "7. ingress-nginx"

INGRESS_READY=$(kubectl get deployment ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.status.readyReplicas}' \
    2>/dev/null || echo 0)

INGRESS_READY="${INGRESS_READY:-0}"

if [[ "$INGRESS_READY" -ge 1 ]]; then

    pass "ingress-nginx controller is running."

else

    fail "ingress-nginx controller is not ready."

fi

echo
kubectl get pods -n ingress-nginx -o wide 2>/dev/null || true

subheader "Ingress Admission Webhook"

WEBHOOK_ENDPOINT=$(kubectl get endpoints \
    ingress-nginx-controller-admission \
    -n ingress-nginx \
    -o jsonpath='{.subsets[0].addresses[0].ip}' \
    2>/dev/null || true)

if [[ -n "$WEBHOOK_ENDPOINT" ]]; then

    pass "Ingress admission endpoint exists: ${WEBHOOK_ENDPOINT}:8443"

    if command -v curl >/dev/null 2>&1; then

        if curl \
            -k \
            --connect-timeout 3 \
            -s \
            "https://${WEBHOOK_ENDPOINT}:8443/healthz" \
            >/dev/null 2>&1; then

            pass "Control plane can reach ingress admission webhook."

        else

            info "Webhook endpoint is present. Health URL did not return a successful HTTP status."

        fi

    else

        info "curl is not installed; direct webhook test skipped."

    fi

else

    fail "No ingress admission webhook endpoint found."

fi

# ------------------------------------------------------------
# 8. cert-manager
# ------------------------------------------------------------

header "8. cert-manager"

CERT_MANAGER_PODS=$(kubectl get pods \
    -n cert-manager \
    --no-headers \
    2>/dev/null || true)

if [[ -z "$CERT_MANAGER_PODS" ]]; then

    fail "No cert-manager pods found."

else

    CERT_BAD=$(echo "$CERT_MANAGER_PODS" |
        awk '$3 != "Running" && $3 != "Completed" {print}')

    if [[ -z "$CERT_BAD" ]]; then

        pass "All cert-manager pods are running."

    else

        fail "One or more cert-manager pods are unhealthy."
        echo
        echo "$CERT_BAD"

    fi

fi

echo
kubectl get pods -n cert-manager -o wide 2>/dev/null || true

# ------------------------------------------------------------
# 9. Application Namespace
# ------------------------------------------------------------

header "9. Application Namespace"

if kubectl get namespace "$APP_NAMESPACE" >/dev/null 2>&1; then

    pass "Namespace '$APP_NAMESPACE' exists."

else

    fail "Namespace '$APP_NAMESPACE' does not exist."

fi

# ------------------------------------------------------------
# 10. NGINX Deployment
# ------------------------------------------------------------

header "10. NGINX Deployment"

if kubectl get deployment "$APP_NAME" \
    -n "$APP_NAMESPACE" \
    >/dev/null 2>&1; then

    pass "NGINX deployment exists."

    READY=$(kubectl get deployment "$APP_NAME" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' \
        2>/dev/null || echo 0)

    DESIRED=$(kubectl get deployment "$APP_NAME" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.spec.replicas}' \
        2>/dev/null || echo 0)

    READY="${READY:-0}"
    DESIRED="${DESIRED:-0}"

    if [[ "$READY" == "$DESIRED" && "$READY" != "0" ]]; then

        pass "NGINX deployment replicas are healthy ($READY/$DESIRED)."

    else

        fail "NGINX replicas are not healthy ($READY/$DESIRED)."

    fi

else

    fail "NGINX deployment not found in namespace '$APP_NAMESPACE'."

fi

echo
kubectl get pods -n "$APP_NAMESPACE" -o wide 2>/dev/null || true

# ------------------------------------------------------------
# 11. NGINX Service
# ------------------------------------------------------------

header "11. NGINX Service"

if kubectl get service "$APP_NAME" \
    -n "$APP_NAMESPACE" \
    >/dev/null 2>&1; then

    SERVICE_IP=$(kubectl get service "$APP_NAME" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.spec.clusterIP}' \
        2>/dev/null || true)

    pass "NGINX service exists (ClusterIP: $SERVICE_IP)."

else

    fail "NGINX service does not exist."

fi

ENDPOINTS=$(kubectl get endpoints "$APP_NAME" \
    -n "$APP_NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' \
    2>/dev/null || true)

if [[ -n "$ENDPOINTS" ]]; then

    pass "NGINX service has backend endpoint(s): $ENDPOINTS"

else

    fail "NGINX service has no backend endpoints."

fi

# ------------------------------------------------------------
# 12. NGINX Ingress
# ------------------------------------------------------------

header "12. NGINX Ingress"

INGRESS_HOST=""

if kubectl get ingress "$APP_NAME" \
    -n "$APP_NAMESPACE" \
    >/dev/null 2>&1; then

    pass "NGINX ingress exists."

    INGRESS_HOST=$(kubectl get ingress "$APP_NAME" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.spec.rules[0].host}' \
        2>/dev/null || true)

    if [[ -n "$INGRESS_HOST" ]]; then

        pass "Ingress hostname detected: $INGRESS_HOST"

    else

        fail "Unable to determine hostname from NGINX Ingress."

    fi

else

    fail "NGINX ingress does not exist."

fi

echo
kubectl get ingress -n "$APP_NAMESPACE" 2>/dev/null || true

# ------------------------------------------------------------
# 13. RBAC Validation
# ------------------------------------------------------------

header "13. RBAC Validation"

if [[ -f "$RBAC_KUBECONFIG" ]]; then

    pass "RBAC user kubeconfig found: $RBAC_KUBECONFIG"

    subheader "RBAC Identity"

    RBAC_ACTUAL_USER=$(kubectl auth whoami \
        --kubeconfig="$RBAC_KUBECONFIG" \
        -o jsonpath='{.status.userInfo.username}' \
        2>/dev/null || true)

    if [[ "$RBAC_ACTUAL_USER" == "$RBAC_USER" ]]; then

        pass "Certificate authenticates as $RBAC_USER."

    else

        fail "Expected $RBAC_USER but authenticated as '$RBAC_ACTUAL_USER'."

    fi

    subheader "Allowed Permissions"

    if kubectl auth can-i create deployments \
        -n "$APP_NAMESPACE" \
        --kubeconfig="$RBAC_KUBECONFIG" \
        2>/dev/null |
        grep -q '^yes$'; then

        pass "$RBAC_USER CAN create deployments in '$APP_NAMESPACE'."

    else

        fail "$RBAC_USER CANNOT create deployments in '$APP_NAMESPACE'."

    fi

    if kubectl auth can-i create services \
        -n "$APP_NAMESPACE" \
        --kubeconfig="$RBAC_KUBECONFIG" \
        2>/dev/null |
        grep -q '^yes$'; then

        pass "$RBAC_USER CAN create services in '$APP_NAMESPACE'."

    else

        fail "$RBAC_USER CANNOT create services in '$APP_NAMESPACE'."

    fi

    if kubectl auth can-i create ingresses.networking.k8s.io \
        -n "$APP_NAMESPACE" \
        --kubeconfig="$RBAC_KUBECONFIG" \
        2>/dev/null |
        grep -q '^yes$'; then

        pass "$RBAC_USER CAN create ingresses in '$APP_NAMESPACE'."

    else

        fail "$RBAC_USER CANNOT create ingresses in '$APP_NAMESPACE'."

    fi

    subheader "Denied Permissions / Least Privilege"

    DEFAULT_RESULT=$(kubectl auth can-i create deployments \
        -n default \
        --kubeconfig="$RBAC_KUBECONFIG" \
        2>/dev/null || true)

    if [[ "$DEFAULT_RESULT" == "no" ]]; then

        pass "$RBAC_USER correctly CANNOT create deployments in default namespace."

    else

        fail "$RBAC_USER unexpectedly CAN create deployments in default namespace."

    fi

    SYSTEM_RESULT=$(kubectl auth can-i get pods \
        -n kube-system \
        --kubeconfig="$RBAC_KUBECONFIG" \
        2>/dev/null || true)

    if [[ "$SYSTEM_RESULT" == "no" ]]; then

        pass "$RBAC_USER correctly CANNOT access kube-system pods."

    else

        fail "$RBAC_USER unexpectedly CAN access kube-system pods."

    fi

    NODE_RESULT=$(kubectl auth can-i get nodes \
        --kubeconfig="$RBAC_KUBECONFIG" \
        2>/dev/null || true)

    if [[ "$NODE_RESULT" == "no" ]]; then

        pass "$RBAC_USER correctly CANNOT access cluster-level Node resources."

    else

        fail "$RBAC_USER unexpectedly CAN access cluster-level Node resources."

    fi

else

    warn "RBAC kubeconfig '$RBAC_KUBECONFIG' not found; RBAC tests skipped."

fi

# ------------------------------------------------------------
# 14. Application Connectivity
# ------------------------------------------------------------

header "14. Application Connectivity"

HTTP_NODEPORT=$(kubectl get service ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' \
    2>/dev/null || true)

HTTPS_NODEPORT=$(kubectl get service ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}' \
    2>/dev/null || true)

if [[ -n "$HTTP_NODEPORT" ]]; then

    pass "Ingress HTTP NodePort detected: $HTTP_NODEPORT"

else

    fail "Unable to determine ingress-nginx HTTP NodePort."

fi

if [[ -n "$HTTPS_NODEPORT" ]]; then

    pass "Ingress HTTPS NodePort detected: $HTTPS_NODEPORT"

else

    warn "Unable to determine ingress-nginx HTTPS NodePort."

fi

if [[ -n "$INGRESS_HOST" && -n "$HTTP_NODEPORT" ]]; then

    HTTP_URL="http://${EXPECTED_CONTROLPLANE_IP}:${HTTP_NODEPORT}"

    info "Testing HTTP application path."
    info "URL: $HTTP_URL"
    info "Host header: $INGRESS_HOST"

    HTTP_CODE=$(curl \
        -s \
        -o /tmp/nginx-verification-http.html \
        -w "%{http_code}" \
        --connect-timeout 5 \
        -H "Host: ${INGRESS_HOST}" \
        "$HTTP_URL" \
        2>/dev/null || true)

    HTTP_CODE="${HTTP_CODE:-000}"

    if [[ "$HTTP_CODE" == "200" ]]; then

        pass "NGINX returned HTTP 200 through ingress."

    elif [[ "$HTTP_CODE" == "301" ||
            "$HTTP_CODE" == "302" ||
            "$HTTP_CODE" == "307" ||
            "$HTTP_CODE" == "308" ]]; then

        pass "Ingress correctly redirected HTTP to HTTPS (HTTP $HTTP_CODE)."

    elif [[ "$HTTP_CODE" == "404" ]]; then

        fail "Ingress returned HTTP 404. Request reached ingress-nginx but did not match the configured Ingress rule."

    elif [[ "$HTTP_CODE" == "000" ]]; then

        fail "Unable to establish HTTP connection to ingress-nginx."

    else

        warn "NGINX ingress returned unexpected HTTP status $HTTP_CODE."

    fi

else

    fail "Unable to perform HTTP Ingress test because hostname or NodePort is missing."

fi

if [[ -n "$INGRESS_HOST" && -n "$HTTPS_NODEPORT" ]]; then

    HTTPS_URL="https://${EXPECTED_CONTROLPLANE_IP}:${HTTPS_NODEPORT}"

    info "Testing HTTPS application path."
    info "URL: $HTTPS_URL"
    info "Host header: $INGRESS_HOST"

    HTTPS_CODE=$(curl \
        -k \
        -s \
        -o /tmp/nginx-verification-https.html \
        -w "%{http_code}" \
        --connect-timeout 5 \
        -H "Host: ${INGRESS_HOST}" \
        "$HTTPS_URL" \
        2>/dev/null || true)

    HTTPS_CODE="${HTTPS_CODE:-000}"

    if [[ "$HTTPS_CODE" == "200" ]]; then

        pass "NGINX returned HTTPS 200 through ingress."

    elif [[ "$HTTPS_CODE" == "404" ]]; then

        fail "HTTPS reached ingress-nginx but did not match the configured Ingress rule."

    elif [[ "$HTTPS_CODE" == "000" ]]; then

        fail "Unable to establish HTTPS connection to ingress-nginx."

    else

        warn "HTTPS ingress returned unexpected HTTP status $HTTPS_CODE."

    fi

fi

# ------------------------------------------------------------
# 15. Certificate Resources
# ------------------------------------------------------------

header "15. Certificate Resources"

CERT_COUNT=$(kubectl get certificates \
    -n "$APP_NAMESPACE" \
    --no-headers \
    2>/dev/null |
    wc -l |
    tr -d ' ')

if [[ "$CERT_COUNT" -gt 0 ]]; then

    echo
    kubectl get certificates -n "$APP_NAMESPACE"

    NOT_READY=$(kubectl get certificates \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
        2>/dev/null |
        awk '$2 != "True" {print}')

    if [[ -z "$NOT_READY" ]]; then

        pass "All Certificate resources report Ready."

    else

        warn "One or more Certificate resources are not Ready."
        echo
        echo "$NOT_READY"

    fi

else

    info "No Certificate resources found in namespace '$APP_NAMESPACE'."

fi

# ------------------------------------------------------------
# 16. User Certificate Authentication
# ------------------------------------------------------------

header "16. User Certificate Authentication"

if [[ -f "$RBAC_KUBECONFIG" ]]; then

    RBAC_CERT_USER=$(kubectl auth whoami \
        --kubeconfig="$RBAC_KUBECONFIG" \
        -o jsonpath='{.status.userInfo.username}' \
        2>/dev/null || true)

    if [[ "$RBAC_CERT_USER" == "$RBAC_USER" ]]; then

        pass "Client certificate successfully authenticates as $RBAC_USER."

    else

        fail "Client certificate authentication failed. Expected '$RBAC_USER' but received '$RBAC_CERT_USER'."

    fi

else

    fail "RBAC kubeconfig '$RBAC_KUBECONFIG' not found."

fi

CSR_MATCH=$(kubectl get csr \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.username}{"|"}{range .status.conditions[*]}{.type}{" "}{end}{"\n"}{end}' \
    2>/dev/null |
    awk -F'|' -v user="$RBAC_USER" '$2 == user {print; exit}')

if [[ -n "$CSR_MATCH" ]]; then

    CSR_NAME=$(echo "$CSR_MATCH" | cut -d'|' -f1)
    CSR_STATUS=$(echo "$CSR_MATCH" | cut -d'|' -f3)

    if [[ "$CSR_STATUS" == *"Approved"* ]]; then

        pass "CSR '$CSR_NAME' exists and is approved."

    else

        warn "CSR '$CSR_NAME' exists but does not show Approved status."

    fi

else

    info "No current CSR object found for $RBAC_USER; existing client certificate authentication is valid."

fi

# ------------------------------------------------------------
# 17. RBAC Resources
# ------------------------------------------------------------

header "17. RBAC Resources"

ROLEBINDING=$(kubectl get rolebindings \
    -n "$APP_NAMESPACE" \
    -o jsonpath="{range .items[*]}{.metadata.name}{'|'}{range .subjects[*]}{.kind}{':'}{.name}{' '}{end}{'\n'}{end}" \
    2>/dev/null |
    awk -F'|' -v user="$RBAC_USER" '$2 ~ "User:" user {print $1; exit}')

if [[ -z "$ROLEBINDING" ]]; then

    fail "No RoleBinding found for $RBAC_USER in '$APP_NAMESPACE'."

else

    pass "Found RoleBinding: $ROLEBINDING"

    ROLE_KIND=$(kubectl get rolebinding "$ROLEBINDING" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.roleRef.kind}' \
        2>/dev/null || true)

    ROLE_NAME=$(kubectl get rolebinding "$ROLEBINDING" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{.roleRef.name}' \
        2>/dev/null || true)

    if [[ -n "$ROLE_NAME" ]]; then

        pass "RoleBinding references ${ROLE_KIND}/${ROLE_NAME}."

    else

        fail "Unable to determine Role referenced by RoleBinding '$ROLEBINDING'."

    fi

    BOUND_USERS=$(kubectl get rolebinding "$ROLEBINDING" \
        -n "$APP_NAMESPACE" \
        -o jsonpath='{range .subjects[?(@.kind=="User")]}{.name}{" "}{end}' \
        2>/dev/null || true)

    if [[ "$BOUND_USERS" == *"$RBAC_USER"* ]]; then

        pass "RoleBinding correctly grants access to $RBAC_USER."

    else

        fail "RoleBinding does not contain $RBAC_USER as a User subject."

    fi

    if [[ "$ROLE_KIND" == "Role" ]]; then

        if kubectl get role "$ROLE_NAME" \
            -n "$APP_NAMESPACE" \
            >/dev/null 2>&1; then

            pass "Referenced Role '$ROLE_NAME' exists in '$APP_NAMESPACE'."

        else

            fail "Referenced Role '$ROLE_NAME' does not exist in '$APP_NAMESPACE'."

        fi

    elif [[ "$ROLE_KIND" == "ClusterRole" ]]; then

        if kubectl get clusterrole "$ROLE_NAME" \
            >/dev/null 2>&1; then

            pass "Referenced ClusterRole '$ROLE_NAME' exists."

        else

            fail "Referenced ClusterRole '$ROLE_NAME' does not exist."

        fi

    else

        fail "Unexpected roleRef kind '$ROLE_KIND'."

    fi

fi

# ------------------------------------------------------------
# 18. ClusterRoleBinding Safety Check
# ------------------------------------------------------------

header "18. ClusterRoleBinding Safety Check"

CLUSTER_BINDINGS=$(kubectl get clusterrolebindings \
    -o jsonpath="{range .items[*]}{.metadata.name}{'|'}{range .subjects[*]}{.kind}{':'}{.name}{' '}{end}{'\n'}{end}" \
    2>/dev/null |
    awk -F'|' -v user="$RBAC_USER" '$2 ~ "User:" user {print $1}')

if [[ -z "$CLUSTER_BINDINGS" ]]; then

    pass "$RBAC_USER has no direct ClusterRoleBinding."

else

    fail "$RBAC_USER has direct ClusterRoleBinding(s): $CLUSTER_BINDINGS"

fi

# ------------------------------------------------------------
# 19. Final Resource Overview
# ------------------------------------------------------------

header "19. Final Resource Overview"

kubectl get \
    deployments,pods,services,ingresses \
    -n "$APP_NAMESPACE" \
    -o wide \
    2>/dev/null || true

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

header "VALIDATION SUMMARY"

TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))

printf "%-20s %s\n" "Total Checks:" "$TOTAL"
printf "${GREEN}%-20s %s${NC}\n" "Passed:" "$PASS_COUNT"
printf "${YELLOW}%-20s %s${NC}\n" "Warnings:" "$WARN_COUNT"
printf "${RED}%-20s %s${NC}\n" "Failed:" "$FAIL_COUNT"

echo

if [[ "$FAIL_COUNT" -eq 0 ]]; then

    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD} CLUSTER VALIDATION SUCCESSFUL${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"

    echo
    echo "The Kubernetes cluster appears operational."
    echo
    echo "Validated:"
    echo "  - Kubernetes API"
    echo "  - Control plane and worker nodes"
    echo "  - Correct 192.168.56.x node networking"
    echo "  - Flannel CNI"
    echo "  - Flannel eth1 interface selection"
    echo "  - CoreDNS"
    echo "  - ingress-nginx"
    echo "  - Ingress admission endpoint"
    echo "  - cert-manager"
    echo "  - nginx-demo namespace"
    echo "  - NGINX Deployment"
    echo "  - NGINX Service and endpoints"
    echo "  - NGINX Ingress"
    echo "  - HTTP ingress routing"
    echo "  - HTTPS ingress routing"
    echo "  - Certificate-based nginx-user authentication"
    echo "  - Namespace-scoped RBAC permissions"
    echo "  - Least-privilege access restrictions"
    echo "  - RoleBinding and Role relationship"
    echo "  - No direct cluster-wide RBAC grant"
    echo

    if [[ "$WARN_COUNT" -gt 0 ]]; then

        echo -e "${YELLOW}Validation completed with $WARN_COUNT warning(s).${NC}"
        echo "Review warnings above to determine whether action is required."
        echo

    else

        echo -e "${GREEN}${BOLD}All validation checks completed without warnings.${NC}"
        echo

    fi

    exit 0

else

    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD} CLUSTER VALIDATION FAILED${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"

    echo
    echo "One or more validation checks failed."
    echo
    echo "Review the [FAIL] results above before continuing."
    echo

    exit 1

fi
