#!/usr/bin/env bash
set -euo pipefail

### ============================================================
###  SETUP VARIABLES
### ============================================================

PROJECT="a083gt"
ENV="prod"
LABEL="Prod"
PROJECT_ID="${PROJECT}-${ENV}"

VPC_NETWORK="bcr-vpc-${ENV}"
VPC_HOST_PROJECT="c4hnrd"
VPC_HOST_PROJECT_ID="${VPC_HOST_PROJECT}-${ENV}"

VPC_SUBNET="bcr-common-${ENV}-montreal"
REGION="northamerica-northeast1"
ZONE="northamerica-northeast1-a"
APP="namex"

TAGS="${APP}-solr"

ARTIFACT_REGISTRY_PROJECT="c4hnrd-tools"
BOOT_DISK_IMAGE="cos-121-18867-199-38"
# PROD SIZES
MACHINE_TYPE_FOLLOWER="custom-1-8192-ext"
BOOT_DISK_SIZE_FOLLOWER="16GiB"

MACHINE_TYPE_LEADER="custom-2-10240"
BOOT_DISK_SIZE_LEADER="24GiB"

FOLLOWER_ROLE="follower"
LEADER_ROLE="leader"

FOLLOWER_GRP_NAME="${APP}-solr-${FOLLOWER_ROLE}-grp-${ENV}"
LEADER_GRP_NAME="${APP}-solr-${LEADER_ROLE}-grp-${ENV}"
INSTANCE_TEMPLATE_FOLLOWER="${APP}-solr-${FOLLOWER_ROLE}-vm-tmpl-${ENV}"
INSTANCE_TEMPLATE_LEADER="${APP}-solr-${LEADER_ROLE}-vm-tmpl-${ENV}"

FOLLOWER_JVM_MEM="1g"
LEADER_JVM_MEM="2g"

FOLLOWER_IMAGE="name-request-solr-${FOLLOWER_ROLE}"
LEADER_IMAGE="name-request-solr-${LEADER_ROLE}"

IMAGE_PROJECT="${VPC_HOST_PROJECT}-tools"
IMAGE_REPO="vm-repo"

HEALTH_CHECK_NAME="${APP}-solr-health-check-$ENV"

SERVICE_ACCOUNT=$(gcloud iam service-accounts list \
  --format="value(email)" \
  --filter 'displayName="Default compute service account"' \
  --project="$PROJECT_ID")

## ============================================================
##  ARTIFACT REGISTRY PERMISSIONS
## ============================================================

echo "➤ Adding artifact registry pull permissions..."

gcloud projects add-iam-policy-binding "$ARTIFACT_REGISTRY_PROJECT" \
  --member "serviceAccount:${SERVICE_ACCOUNT}" \
  --role "roles/artifactregistry.serviceAgent"


### ============================================================
###  ASSIGN INTERNAL STATIC IPs
### ============================================================

echo "➤ Creating internal load balancer IPs..."

LB_LEADER_IP=$(gcloud compute addresses create ${APP}-solr-ilb-ip \
  --region="$REGION" \
  --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
  --project="$PROJECT_ID" \
  --format="value(address)")

LB_FOLLOWER_IP=$(gcloud compute addresses create ${APP}-solr-follower-ilb-ip \
  --region="$REGION" \
  --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
  --project="$PROJECT_ID" \
  --format="value(address)")


echo "  Leader ILB IP:   $LB_LEADER_IP"
echo "  Follower ILB IP: $LB_FOLLOWER_IP"

### ============================================================
###  SOLR INSTANCE GROUPS
### ============================================================

echo "➤ Creating instance groups..."

gcloud compute instance-groups unmanaged create "$FOLLOWER_GRP_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE"

gcloud compute instance-groups unmanaged set-named-ports "$FOLLOWER_GRP_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" \
  --named-ports=http:8983

gcloud compute instance-groups unmanaged create "$LEADER_GRP_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE"

gcloud compute instance-groups unmanaged set-named-ports "$LEADER_GRP_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" \
  --named-ports=http:8983

### ============================================================
###  HEALTH CHECK
### ============================================================
echo "➤ Creating health check..."

gcloud compute health-checks create tcp "$HEALTH_CHECK_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --port=8983 \
  --check-interval=5s \
  --timeout=5s \
  --unhealthy-threshold=2 \
  --healthy-threshold=2

### ============================================================
###  FIREWALL RULES
### ============================================================

echo "➤ Creating firewall rules for ILB and health checks..."

gcloud compute firewall-rules create allow-${APP}-solr-ilb-hc \
  --priority=1000 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:8983 \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --network="$VPC_NETWORK" \
  --target-tags="$TAGS" \
  --project="$VPC_HOST_PROJECT_ID"

LB_SUBNET_CIDR=$(gcloud compute networks subnets describe "$VPC_SUBNET" \
  --region="$REGION" \
  --project="$VPC_HOST_PROJECT_ID" \
  --format="value(ipCidrRange)")

gcloud compute firewall-rules create allow-${APP}-solr-ilb \
  --priority=1000 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:8983 \
  --source-ranges="$LB_SUBNET_CIDR" \
  --network="$VPC_NETWORK" \
  --target-tags="$TAGS" \
  --project="$VPC_HOST_PROJECT_ID"

  ## ============================================================
  ##  SOLR INSTANCE TEMPLATES (with metadata including ZONE)
  ## ============================================================

  echo "➤ Creating SOLR instance templates..."
  DEVICE_NAME="${APP}-solr-disk-$ENV"
  PATH_TO_STARTUP_SCRIPT="${APP}-solr/startupscript.txt"

  gcloud compute instance-templates create "$INSTANCE_TEMPLATE_FOLLOWER" \
    --project="$PROJECT_ID" \
    --machine-type="$MACHINE_TYPE_FOLLOWER" \
    --network-interface=network=projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK,subnet=projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET,stack-type=IPV4_ONLY,no-address \
    --metadata-from-file=startup-script="$PATH_TO_STARTUP_SCRIPT" \
    --metadata=google-logging-enabled=true,role=$FOLLOWER_ROLE,env=$ENV,label=$LABEL,jvm_mem=$FOLLOWER_JVM_MEM,image=$FOLLOWER_IMAGE,image_project=$IMAGE_PROJECT,image_repo=$IMAGE_REPO,zone=$ZONE \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --tags="$TAGS" \
    --create-disk=auto-delete=yes,boot=yes,device-name="$DEVICE_NAME",image=projects/cos-cloud/global/images/$BOOT_DISK_IMAGE,mode=rw,size="$BOOT_DISK_SIZE_FOLLOWER",type=pd-ssd \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring


  gcloud compute instance-groups set-named-ports "$FOLLOWER_GRP_NAME" \
    --named-ports http:8983 \
    --zone="$ZONE" \
    --project="$PROJECT_ID"

  gcloud compute instance-templates create "$INSTANCE_TEMPLATE_LEADER" \
    --project="$PROJECT_ID" \
    --machine-type="$MACHINE_TYPE_LEADER" \
    --network-interface=network=projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK,subnet=projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET,stack-type=IPV4_ONLY,no-address \
    --metadata-from-file=startup-script="$PATH_TO_STARTUP_SCRIPT" \
    --metadata=google-logging-enabled=true,role=$LEADER_ROLE,env=$ENV,label=$LABEL,jvm_mem=$LEADER_JVM_MEM,image=$LEADER_IMAGE,image_project=$IMAGE_PROJECT,image_repo=$IMAGE_REPO,zone=$ZONE \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
    --tags="$TAGS" \
    --create-disk=auto-delete=yes,boot=yes,device-name="$DEVICE_NAME",image=projects/cos-cloud/global/images/$BOOT_DISK_IMAGE,mode=rw,size="$BOOT_DISK_SIZE_LEADER",type=pd-ssd \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring

  gcloud compute instance-groups set-named-ports "$LEADER_GRP_NAME" \
    --named-ports http:8983 \
    --zone="$ZONE" \
    --project="$PROJECT_ID"

## ============================================================
##  LOAD BALANCERS (Leader & Follower)
## ============================================================

echo "➤ Creating backend services and ILB forwarding rules..."

gcloud compute backend-services create ${APP}-solr-leader-backend \
  --protocol=TCP \
  --health-checks="$HEALTH_CHECK_NAME" \
  --health-checks-region="$REGION" \
  --region="$REGION" \
  --load-balancing-scheme=INTERNAL \
  --project="$PROJECT_ID"

gcloud compute backend-services create ${APP}-solr-follower-backend \
  --protocol=TCP \
  --health-checks="$HEALTH_CHECK_NAME" \
  --health-checks-region="$REGION" \
  --region="$REGION" \
  --load-balancing-scheme=INTERNAL \
  --project="$PROJECT_ID"

  gcloud compute forwarding-rules create ${APP}-solr-tcp-ilb-rule \
    --load-balancing-scheme=INTERNAL \
    --network="projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK" \
    --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
    --address="$LB_LEADER_IP" \
    --ports=8983 \
    --backend-service=${APP}-solr-leader-backend \
    --backend-service-region="$REGION" \
    --region="$REGION" \
    --project="$PROJECT_ID"

  gcloud compute forwarding-rules create ${APP}-solr-follower-ilb-rule \
    --load-balancing-scheme=INTERNAL \
    --network="projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK" \
    --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
    --address="$LB_FOLLOWER_IP" \
    --ports=8983 \
    --backend-service=${APP}-solr-follower-backend \
    --backend-service-region="$REGION" \
    --region="$REGION" \
    --project="$PROJECT_ID"

  NEW_LEADER_VM="${APP}-solr-${LEADER_ROLE}-$(date -u +"%Y-%m-%d--%H%M%S")"

  echo "➤ Creating leader VM: $NEW_LEADER_VM from template $INSTANCE_TEMPLATE_LEADER"
  gcloud compute instances create "$NEW_LEADER_VM" \
    --source-instance-template "$INSTANCE_TEMPLATE_LEADER" \
    --zone "$ZONE" \
    --project "$PROJECT_ID"

NEW_FOLLOWER_VM="${APP}-solr-${FOLLOWER_ROLE}-$(date -u +"%Y-%m-%d--%H%M%S")"

echo "➤ Creating follower VM: $NEW_FOLLOWER_VM from template $INSTANCE_TEMPLATE_FOLLOWER"
gcloud compute instances create "$NEW_FOLLOWER_VM" \
  --source-instance-template "$INSTANCE_TEMPLATE_FOLLOWER" \
  --zone "$ZONE" \
  --project "$PROJECT_ID"

gcloud compute instance-groups unmanaged add-instances "$LEADER_GRP_NAME" \
  --zone="$ZONE" \
  --instances="$NEW_LEADER_VM" \
  --project="$PROJECT_ID"

gcloud compute instance-groups unmanaged add-instances "$FOLLOWER_GRP_NAME" \
  --zone="$ZONE" \
  --instances="$NEW_FOLLOWER_VM" \
  --project="$PROJECT_ID"

gcloud compute backend-services add-backend ${APP}-solr-leader-backend \
  --instance-group="$LEADER_GRP_NAME" \
  --instance-group-zone="$ZONE" \
  --region="$REGION" \
  --project="$PROJECT_ID"

gcloud compute backend-services add-backend ${APP}-solr-follower-backend \
  --instance-group="$FOLLOWER_GRP_NAME" \
  --instance-group-zone="$ZONE" \
  --region="$REGION" \
  --project="$PROJECT_ID"

echo "✔ SOLR infrastructure creation complete!"
echo "Next step: Deploy & create Solr VMs."
