# SOLR Infrastructure Deployment Script

This repository contains a Bash script to automate the deployment of a SOLR cluster in Google Cloud Platform (GCP) using a leader/follower architecture. The script sets up instance templates, unmanaged instance groups, internal load balancers (ILB), health checks, firewall rules, and creates SOLR VMs.

---

## Prerequisites

Before running the script, ensure the following:

- Google Cloud SDK installed and authenticated.
- `gcloud` command-line tool is configured for your project.
- Proper IAM roles are assigned to your service accounts.
- Artifact Registry and required images exist.
- Startup script file exists at the specified path: `namex-solr/startupscript.txt`.

---

## Usage

Make sure to populate desired variable values correctly, e.g. ENV, LABEL, etc.

```
chmod +x gcp-solr-infra.sh
./documentation/gcp-solr-infra.sh.sh
```
it is important to run this from 1 level higher as the script references location of startup.txt

⚠️ **Important Notes:**

- The script is fragile and may fail if resources are missing or already exist.
- You may need to set up the service account permissions for common project artifact registry manually.
- Zone-specific resource availability may block VM creation; you may need to wait for the resources to become available.

## Leader/Follower SOLR Replication

After VM creation, SOLR replication needs manual configuration:

1. SSH into a follower VM.
2. Set the leader URL using curl:

```
curl -X POST -H 'Content-type: application/json' \
  -d '{"set-user-property":{"solr.leaderUrl":"http://<LEADER_INTERNAL_IP>:8983/solr/name_request"}}' \
  http://<FOLLOWER_INTERNAL_IP>:8983/solr/name_request_follower/config/requestHandler?componentName=/replication
```
You can verify that it succeeded via

```
curl "http://<FOLLOWER_INTERNAL_IP>:8983/solr/name_request_follower/config/requestHandler?componentName=/replication"
```
You should see smth like:
```
{
  "responseHeader":{
    "status":0,
    "QTime":0
  },
  "config":{
    "requestHandler":{
      "/replication":{
        "name":"/replication",
        "class":"solr.ReplicationHandler",
        "follower":{
          "leaderUrl":"http://<LEADER_INTERNAL_IP>:8983/solr/name_request",
          "pollInterval":"00:00:30",
          "compression":"internal"
        }
      }
    }
  }
}
```
You can also verify data load has been loaded to the follower:

```
curl -v http://<FOLLOWER_INTERNAL_IP>:8983/solr/admin/cores?action=STATUS

```
You should see non-empty follower core:
```
{
  "responseHeader":{
    "status":0,
    "QTime":133
  },
  "initFailures":{ },
  "status":{
    "name_request_follower":{
      "name":"name_request_follower",
      "instanceDir":"/var/solr/data/name_request_follower",
      "dataDir":"/var/solr/data/name_request_follower/data/",
      "config":"solrconfig.xml",
      "schema":"managed-schema.xml",
      "startTime":"2025-12-11T18:53:38.144Z",
      "uptime":8710669,
      "index":{
        "numDocs":8784132,
        "maxDoc":8784134,
        "deletedDocs":2,
        "version":806,
        "segmentCount":31,
        "current":true,
        "hasDeletions":true,
        "directory":"org.apache.lucene.store.NRTCachingDirectory:NRTCachingDirectory(MMapDirectory@/var/solr/data/name_request_follower/data/index lockFactory=org.apache.lucene.store.NativeFSLockFactory@5732c8fc; maxCacheMB=48.0 maxMergeSizeMB=4.0)",
        "segmentsFile":"segments_1j",
        "segmentsFileSizeInBytes":2713,
        "userData":{
          "commitCommandVer":"1851235944050458624",
          "commitTimeMSec":"1765476173449"
        },
        "lastModified":"2025-12-11T18:02:53.449Z",
        "sizeInBytes":3830194266,
        "size":"3.57 GB"
      }
    }
  }
```
