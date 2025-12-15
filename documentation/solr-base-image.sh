#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

PROJECT="a083gt"
ENV="test"
PROJECT_ID="${PROJECT}-${ENV}"

APP="namex"
ZONE="northamerica-northeast1-a"
REGION="northamerica-northeast1"

TEMPLATE_VERSION="v2"
BOOT_DISK_IMAGE="cos-121-XXXXX-XXX-XX"

SERVICE_ACCOUNT=$(gcloud iam service-accounts list \
  --format="value(email)" \
  --filter 'displayName="Default compute service account"' \
  --project="$PROJECT_ID")

########################################
# TEMPLATE NAMES
########################################

LEADER_TEMPLATE="${APP}-solr-leader-vm-tmpl-${ENV}-${TEMPLATE_VERSION}"
FOLLOWER_TEMPLATE="${APP}-solr-follower-vm-tmpl-${ENV}-${TEMPLATE_VERSION}"

########################################
# CREATE LEADER TEMPLATE
########################################

echo "➤ Creating leader template: $LEADER_TEMPLATE"

gcloud compute instance-templates create "$LEADER_TEMPLATE" \
  --project="$PROJECT_ID" \
  --source-instance-template "${APP}-solr-leader-vm-tmpl-${ENV}" \
  --create-disk=image=projects/cos-cloud/global/images/$BOOT_DISK_IMAGE,boot=yes,auto-delete=yes

########################################
# CREATE FOLLOWER TEMPLATE
########################################

if [[ "$ENV" != "dev" ]]; then
  echo "➤ Creating follower template: $FOLLOWER_TEMPLATE"

  gcloud compute instance-templates create "$FOLLOWER_TEMPLATE" \
    --project="$PROJECT_ID" \
    --source-instance-template "${APP}-solr-follower-vm-tmpl-${ENV}" \
    --create-disk=image=projects/cos-cloud/global/images/$BOOT_DISK_IMAGE,boot=yes,auto-delete=yes
fi

echo "✔ Base image templates created."
echo "Next step: update deploy-solr.sh to reference version ${TEMPLATE_VERSION}"
