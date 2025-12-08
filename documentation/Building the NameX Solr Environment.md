*NOTE: this expects you to already have your gcloud setup / permissions to the gcp environment*

SETUP
```
PROJECT=a083gt
```

```
ENV=test
```

```
PROJECT_ID=$PROJECT-$ENV
```

```
VPC_NETWORK=bcr-vpc-test
```

```
VPC_HOST_PROJECT=c4hnrd
```

```
VPC_HOST_PROJECT_ID=$VPC_HOST_PROJECT-$ENV
```

```
VPC_SUBNET=bcr-common-test-montreal
```

```
REGION=northamerica-northeast1
ZONE=northamerica-northeast1-a
```
Assign internal static IP
```
LB_LEADER_IP=$(gcloud compute addresses create namex-solr-ilb-ip \
  --region="$REGION" \
  --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
  --project="$PROJECT_ID" \
  --format="value(address)")

LB_FOLLOWER_IP=$(gcloud compute addresses create namex-solr-follower-ilb-ip \
  --region="$REGION" \
  --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
  --project="$PROJECT_ID" \
  --format="value(address)")
```


### API Networking Stuff
<!-- 1. Reserve an external static IP for the api <-- probably don't need static IP, for the cloudrun
   ```
   STATIC_IP_NAME=namex-solr-api-ip-$ENV
   ```

   ```
   gcloud compute addresses create $STATIC_IP_NAME --project=$PROJECT_ID --region=northamerica-northeast1
   ```
   *Set the generated static IP (used later)*
   ```
   STATIC_IP=$(gcloud compute addresses list --filter NAME:$STATIC_IP_NAME --project=$PROJECT_ID --format="value(address_range())")
   ``` -->
<!-- 2. Create the router
   ```
   ROUTER_NAME=namex-solr-api-router-$ENV
   ```

   ```
   gcloud compute routers create $ROUTER_NAME --project=$PROJECT_ID --region=northamerica-northeast1 --network=$VPC_NETWORK
   ```
3. Create the NAT gateway
   ```
   NAT_GW_NAME=namex-solr-api-nat-gw-$ENV
   ```

   ```
   gcloud compute routers nats create $NAT_GW_NAME --router=$ROUTER_NAME --region=northamerica-northeast1 --nat-all-subnet-ip-ranges --nat-external-ip-pool=$STATIC_IP_NAME --project=$PROJECT_ID
   ```

4.  Create the vm connector - not neeeded because connector already exists
```
CONNECTOR_NAME=namex-solr-connector-$ENV
```
```
gcloud compute networks vpc-access connectors create $CONNECTOR_NAME --region=northamerica-northeast1 --network=default --range=10.8.0.0/28 --min-instances=2 --max-instances=10 --machine-type=e2-micro --project=$PROJECT_ID
``` -->

### Solr Networking stuff
1. Create instance follower/leader instance groups

   ```
   FOLLOWER_GRP_NAME=namex-solr-follower-grp-$ENV
   ```

   ```
   gcloud compute instance-groups unmanaged create $FOLLOWER_GRP_NAME --project=$PROJECT_ID --zone=northamerica-northeast1-a
   ```

   ```
   gcloud compute instance-groups unmanaged set-named-ports $FOLLOWER_GRP_NAME --project=$PROJECT_ID --zone=northamerica-northeast1-a --named-ports=http:8983
   ```

   ```
   LEADER_GRP_NAME=namex-solr-leader-grp-$ENV
   ```

   ```
   gcloud compute instance-groups unmanaged create $LEADER_GRP_NAME --project=$PROJECT_ID --zone=northamerica-northeast1-a
   ```

   ```
   gcloud compute instance-groups unmanaged set-named-ports $LEADER_GRP_NAME --project=$PROJECT_ID --zone=northamerica-northeast1-a --named-ports=http:8983
   ```
2. Create the health check
    ```
    TAGS=namex-solr
    ```

   ```
   HEALTH_CHECK_NAME=namex-solr-health-check-$ENV

   ```

   ```


   <!-- gcloud compute health-checks create http $HEALTH_CHECK_NAME \
       --region=$REGION \
       --project=$PROJECT_ID \
       --port=8983 \
       --request-path="/solr/admin/info/system" \
       --check-interval=5s \
       --timeout=5s \
       --unhealthy-threshold=2 \
       --healthy-threshold=2 -->


    gcloud compute health-checks create tcp $HEALTH_CHECK_NAME \
       --region=$REGION \
       --project=$PROJECT_ID \
       --port=8983 \
       --check-interval=5s \
       --timeout=5s \
       --unhealthy-threshold=2 \
       --healthy-threshold=2


   ```
3. Add the firewall rule to allow the health check connection
   ```

   gcloud compute firewall-rules create allow-namex-solr-ilb-hc \
       --priority=1000 \
       --direction=INGRESS \
       --action=ALLOW \
       --rules=tcp:8983 \
       --source-ranges=35.191.0.0/16,130.211.0.0/22 \
       --network=$VPC_NETWORK \
       --target-tags=$TAGS \
       --project=$VPC_HOST_PROJECT_ID

       LB_SUBNET_CIDR=$(gcloud compute networks subnets describe $VPC_SUBNET \
         --region=$REGION \
         --project=$VPC_HOST_PROJECT_ID \
         --format="value(ipCidrRange)")

     gcloud compute firewall-rules create allow-namex-solr-ilb \
         --priority=1000 \
         --direction=INGRESS \
         --action=ALLOW \
         --rules=tcp:8983 \
         --source-ranges=$LB_SUBNET_CIDR \
         --network=$VPC_NETWORK \
         --target-tags=$TAGS \
         --project=$VPC_HOST_PROJECT_ID


   ```
<!-- 4. Create a basic cloud armor policy < --- this is only possible if we have external load balancer
   - Create Policy
   - Fill in the name and leave the defaults / create
     *set the name in your shell for later*
      ```
      POLICY_NAME=namex-solr-policy-$ENV
      gcloud compute security-policies create $POLICY_NAME \
      --project=$PROJECT_ID

      OCP_POLICY_NAME=ocp-policy-$ENV
      REGION=northamerica-northeast1

      gcloud compute security-policies create $OCP_POLICY_NAME \
    --project=$PROJECT_ID \
    --region=$REGION      

	  ``` -->
   <!-- - Update the policy to allow the API connection <-- probably don't need as we won't have the static IP
      ```
      ALLOW_API_RULE_NAME=allow-namex-solr-api-access-$ENV
	  ```

      ```
      gcloud compute security-policies rules create 450 --project=$PROJECT_ID --action=allow --security-policy=$POLICY_NAME --src-ip-ranges=$STATIC_IP/32 --description=$ALLOW_API_RULE_NAME
	  ``` -->
   <!-- - Update the policy to allow OCP connection <- this may be not necessary if access api directly
      ```
      ALLOW_OCP_RULE_NAME=allow-OCP-access-$ENV
	  ```

	   ```
     OCP_IP_RANGES="142.34.194.121/32,142.34.194.122/32,142.34.194.123/32,142.34.194.124/32"
	  ```

      ```
      gcloud compute security-policies rules create 500 \
      --project=$PROJECT_ID \
      --region=northamerica-northeast1 \
      --action=allow \
      --security-policy=$OCP_POLICY_NAME \
      --src-ip-ranges="$OCP_IP_RANGES" \
      --description="$ALLOW_OCP_RULE_NAME"

	  ```
    - Switch the default Allow rules to Deny via UI -->

1. Create the follwer/leader load balancers
   - Navigation Menu/Network Services/Load balancing (in the UI)
   - Create Load Balancer
     - Application Load Balancer (HTTP/S) -> next
     - Public facing -> next
     - Global -> next
     - Global external -> next
     - Create
     - Frontend
       - name proxy / keep defaults -> done
     - Backend
       - name service
       - set instance group (follower/leader)
       - set health check to what you created above
       - set cloud armor policy to what you created above
       - create
   - Create
  *(repeat for remaining load balancers -- need one for follower and one for leader)*

  Leader backend
```
gcloud compute backend-services create namex-solr-leader-backend \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=$HEALTH_CHECK_NAME \
    --health-checks-region=$REGION \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --region=$REGION \
    --project=$PROJECT_ID

gcloud compute backend-services add-backend namex-solr-leader-backend \
    --instance-group=$LEADER_GRP_NAME \
    --instance-group-zone=$ZONE \
    --region=$REGION \
    --project=$PROJECT_ID

```
Follower backend
```
gcloud compute backend-services create namex-solr-follower-backend \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=$HEALTH_CHECK_NAME \
    --health-checks-region=$REGION \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --region=$REGION \
    --project=$PROJECT_ID


gcloud compute backend-services add-backend namex-solr-follower-backend \
    --instance-group=$FOLLOWER_GRP_NAME \
    --instance-group-zone=$ZONE \
    --region=$REGION \
    --project=$PROJECT_ID
```
URL map (path-based routing)
```

gcloud compute url-maps create namex-solr-url-map \
  --default-service=$LEADER_BACKEND \
  --region=$REGION \
  --project=$PROJECT_ID

# Full backend URLs
LEADER_BACKEND=$(gcloud compute backend-services describe namex-solr-leader-backend \
  --region="$REGION" --project="$PROJECT_ID" --format="value(selfLink)")
FOLLOWER_BACKEND=$(gcloud compute backend-services describe namex-solr-follower-backend \
  --region="$REGION" --project="$PROJECT_ID" --format="value(selfLink)")


gcloud compute url-maps add-path-matcher namex-solr-url-map \
  --path-matcher-name=solr-path-matcher \
  --default-service="$LEADER_BACKEND" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --path-rules="/leader/*=$LEADER_BACKEND,/follower/*=$FOLLOWER_BACKEND"


  <!-- gcloud compute url-maps import namex-solr-url-map \
      --region=northamerica-northeast1 \
      --project=$PROJECT_ID \
      --source=namex-solr-url-map.json -->
```
Target HTTP proxy
```
gcloud compute target-http-proxies create namex-solr-internal-proxy \
    --url-map=namex-solr-url-map \
    --region=$REGION \
    --project=$PROJECT_ID

```
Internal forwarding rule
```
PROXY_LINK=$(gcloud compute target-http-proxies describe namex-solr-internal-proxy \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(selfLink)")


gcloud compute forwarding-rules create namex-solr-internal-lb-rule \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --ports=80 \
    --network="projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK" \
    --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
    --target-http-proxy="$PROXY_LINK" \
    --region="$REGION" \
    --address="$LB_IP" \
    --project="$PROJECT_ID"

```

Alternative LB set up via TCP

```
gcloud compute backend-services create namex-solr-leader-backend \
    --protocol=TCP \
    --health-checks=$HEALTH_CHECK_NAME \
    --health-checks-region=$REGION \
    --region=$REGION \
    --load-balancing-scheme=INTERNAL \
    --project=$PROJECT_ID

gcloud compute backend-services add-backend namex-solr-leader-backend \
  --instance-group=$LEADER_GRP_NAME \
  --instance-group-zone=$ZONE \
  --region=$REGION \
  --project=$PROJECT_ID


gcloud compute backend-services create namex-solr-follower-backend \
  --protocol=TCP \
  --health-checks=$HEALTH_CHECK_NAME \
  --health-checks-region=$REGION \
  --region=$REGION \
  --load-balancing-scheme=INTERNAL \
  --project=$PROJECT_ID

gcloud compute backend-services add-backend namex-solr-follower-backend \
  --instance-group=$FOLLOWER_GRP_NAME \
  --instance-group-zone=$ZONE \
  --region=$REGION \
  --project=$PROJECT_ID

gcloud compute forwarding-rules create namex-solr-tcp-ilb-rule \
  --load-balancing-scheme=INTERNAL \
  --network="projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK" \
  --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
  --address="$LB_LEADER_IP" \
  --ports=8983 \
  --backend-service=namex-solr-leader-backend \
  --backend-service-region=$REGION \
  --region=$REGION \
  --project=$PROJECT_ID


gcloud compute forwarding-rules create namex-solr-follower-ilb-rule \
  --load-balancing-scheme=INTERNAL \
  --network="projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK" \
  --subnet="projects/$VPC_HOST_PROJECT_ID/regions/$REGION/subnetworks/$VPC_SUBNET" \
  --address="$LB_FOLLOWER_IP" \
  --ports=8983 \
  --backend-service=namex-solr-follower-backend \
  --backend-service-region=$REGION \
  --region=$REGION \
  --project=$PROJECT_ID

```


### SOLR
1. Create the instance templates
   - set variables

     ```
     INSTANCE_TEMPLATE_FOLLOWER=namex-solr-follower-vm-tmpl-$ENV
     ```

     ```
     INSTANCE_TEMPLATE_LEADER=namex-solr-leader-vm-tmpl-$ENV
     ```
     *Set to the default compute service account EMAIL*
     ```
     SERVICE_ACCOUNT=$(gcloud iam service-accounts list --format="value(email)" --filter displayName:"Default compute service account" --project=$PROJECT_ID)
     ```

     ```
     DEVICE_NAME=namex-solr-disk-$ENV
     ```

     ```
     ARTIFACT_REGISTRY_PROJECT=c4hnrd-tools
     ```

     <!-- ```<--- UNUSED
     IMAGE_PATH=$ARTIFACT_REGISTRY_PROJECT/vm-repo
    ```
     ```
     IMAGE_FOLLOWER=$(gcloud artifacts docker images list northamerica-northeast1-docker.pkg.dev/$IMAGE_PATH --filter IMAGE:name-request-solr-follower --format="value(IMAGE)" --limit=1):$ENV
     ```

     ```
     IMAGE_LEADER=$(gcloud artifacts docker images list northamerica-northeast1-docker.pkg.dev/$IMAGE_PATH --filter IMAGE:name-request-solr-leader --format="value(IMAGE)" --limit=1):$ENV
     ``` -->

     ```
     BOOT_DISK_IMAGE=cos-121-18867-199-38
     ```
     ```
     PATH_TO_STARTUP_SCRIPT=namex-solr/startupscript.txt
     ```

     <!-- For DEV (only has Leader instance)
     ```
     MACHINE_TYPE_LEADER=custom-1-5120
     ```
      ```
     BOOT_DISK_SIZE_LEADER=10GiB
     ``` -->
     For TEST
     ```
     MACHINE_TYPE_FOLLOWER=custom-1-5120
     ```
     ```
     BOOT_DISK_SIZE_FOLLOWER=10GiB
     ```
      ```
     MACHINE_TYPE_LEADER=custom-1-5120
     ```
      ```
     BOOT_DISK_SIZE_LEADER=10GiB
     ```
     <!-- For SANDBOX
     ```
     MACHINE_TYPE_FOLLOWER=custom-1-6656
     ```
     ```
     BOOT_DISK_SIZE_FOLLOWER=16GiB
     ```
      ```
     MACHINE_TYPE_LEADER=custom-1-6656
     ```
      ```
     BOOT_DISK_SIZE_LEADER=24GiB
     ```
     For PROD
     ```
     MACHINE_TYPE_FOLLOWER=custom-1-8192-ext
     ```
     ```
     BOOT_DISK_SIZE_FOLLOWER=16GiB
     ```
      ```
     MACHINE_TYPE_LEADER=custom-2-10240
     ```
      ```
     BOOT_DISK_SIZE_LEADER=24GiB
     ``` -->

   -  create the templates. UPDATE THE STARTUP SCRIPT BEFORE RUNNING in namex-solr/startupscript.txt
    ```
    gcloud compute instance-templates create $INSTANCE_TEMPLATE_FOLLOWER --project=$PROJECT_ID --machine-type=$MACHINE_TYPE_FOLLOWER --network-interface=network=projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK,subnet=projects/$VPC_HOST_PROJECT_ID/regions/northamerica-northeast1/subnetworks/$VPC_SUBNET,stack-type=IPV4_ONLY,no-address --metadata=google-logging-enabled=true --metadata-from-file=startup-script=$PATH_TO_STARTUP_SCRIPT --maintenance-policy=MIGRATE --provisioning-model=STANDARD --service-account=$SERVICE_ACCOUNT --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append --tags=$TAGS --create-disk=auto-delete=yes,boot=yes,device-name=$DEVICE_NAME,image=projects/cos-cloud/global/images/$BOOT_DISK_IMAGE,mode=rw,size=$BOOT_DISK_SIZE_FOLLOWER,type=pd-ssd --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any

    gcloud compute instance-groups set-named-ports $LEADER_GRP_NAME \
    --named-ports http:8983 \
    --zone=$ZONE \
    --project=$PROJECT_ID


    ```
    UPDATE THE STARTUP SCRIPT AGAIN BEFORE RUNNING in namex-solr/startupscript.txt

    ```
    gcloud compute instance-templates create $INSTANCE_TEMPLATE_LEADER --project=$PROJECT_ID --machine-type=$MACHINE_TYPE_LEADER --network-interface=network=projects/$VPC_HOST_PROJECT_ID/global/networks/$VPC_NETWORK,subnet=projects/$VPC_HOST_PROJECT_ID/regions/northamerica-northeast1/subnetworks/$VPC_SUBNET,stack-type=IPV4_ONLY,no-address --metadata=google-logging-enabled=true --metadata-from-file=startup-script=$PATH_TO_STARTUP_SCRIPT --maintenance-policy=MIGRATE --provisioning-model=STANDARD --service-account=$SERVICE_ACCOUNT --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append --tags=$TAGS --create-disk=auto-delete=yes,boot=yes,device-name=$DEVICE_NAME,image=projects/cos-cloud/global/images/$BOOT_DISK_IMAGE,mode=rw,size=$BOOT_DISK_SIZE_LEADER,type=pd-ssd --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --reservation-affinity=any


    gcloud compute instance-groups set-named-ports $FOLLOWER_GRP_NAME \
    --named-ports http:8983 \
    --zone=$ZONE \
    --project=$PROJECT_ID

    ```
1. Update permissions to allow this environment to pull the image from tools <-- not sure why we need this? maybe to use for pulling image from common-tools
   ```
   gcloud projects add-iam-policy-binding $ARTIFACT_REGISTRY_PROJECT --member serviceAccount:$SERVICE_ACCOUNT --role=roles/artifactregistry.serviceAgent
   ```
2. *Deploy, create, and load the solr VMs

<!-- ### Scheduler (for SOLR sync via API) <-- i don't think this has been used

```
API_URL=$(gcloud run services describe search-api --platform managed --format 'value(status.url)' --region northamerica-northeast1 --project $PROJECT_ID)/api/v1/internal/solr/update/sync
```

```
gcloud scheduler jobs create http search-solr-sync-job-$ENV --schedule "*/3 * * * *" --uri $API_URL --http-method GET --location northamerica-northeast1 --project $PROJECT_ID
```

### Scheduler (for SOLR sync heartbeat via API)

```
API_URL=$(gcloud run services describe search-api --platform managed --format 'value(status.url)' --region northamerica-northeast1 --project $PROJECT_ID)/api/v1/internal/solr/update/sync/heartbeat
```

```
gcloud scheduler jobs create http search-solr-sync-heartbeat-job-$ENV --schedule "*/15 * * * *" --uri $API_URL --http-method GET --location northamerica-northeast1 --project $PROJECT_ID
``` -->
