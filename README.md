# Fully Private AKS with Azure Monitor Workspace (Prometheus)

[![GitHub](https://img.shields.io/badge/GitHub-jscaravilli%2FAKTAMP-blue?logo=github)](https://github.com/jscaravilli/AKSAMP)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-eastus2-0078D4?logo=microsoftazure)](https://portal.azure.com)

This Terraform configuration demonstrates a **production-ready, fully private AKS cluster** with Azure Monitor Workspace for Prometheus metrics collection, accessed entirely through private endpoints. It deploys a VM and Bastion (optional) for accessing the private workspace.

## Quick Deploy

### Prerequisites
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- Active Azure subscription with appropriate permissions (Contributor or Owner role)

### Before You Deploy

**1. Authenticate with Azure**
```bash
az login
```

**2. Select Your Subscription**

List your subscriptions:
```bash
az account list --output table
```

Set the subscription you want to use:
```bash
az account set --subscription "Your-Subscription-Name-or-ID"
```

Verify the correct subscription is selected:
```bash
az account show --output table
```

> ⚠️ **Important:** Terraform will deploy to whichever subscription is currently selected in Azure CLI. Always verify before running `terraform apply`.

### Deploy in 3 Commands
```bash
git clone https://github.com/jscaravilli/AKSAMP.git
cd AKSAMP
terraform init && terraform apply
```

**Deployment time:** ~15-20 minutes

> **Cost Note:** This deployment includes Azure Bastion (~$140/month). You can disable it by setting `enable_bastion = false` in `terraform.tfvars`.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Azure Virtual Network (10.1.0.0/16)            │
│                                                                         │
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐      │
│  │  AKS Subnet     │  │ Private Endpoint │  │   VM Subnet        │      │
│  │  10.1.1.0/24    │  │ Subnet           │  │   10.1.3.0/24      │      │
│  │                 │  │ 10.1.2.0/24      │  │                    │      │
│  │  ┌───────────┐  │  │                  │  │  ┌──────────────┐  │      │
│  │  │           │  │  │  ┌────────────┐  │  │  │  Windows VM  │  │      │
│  │  │ AKS Nodes │◄─┼──┼──┤  AMPLS PE  │  │  │  │  (Jumpbox)   │  │      │
│  │  │  (2-5)    │  │  │  │ 10.1.2.5   │  │  │  │  10.1.3.4    │  │      │
│  │  │           │  │  │  └─────┬──────┘  │  │  └───────▲──────┘  │      │
│  │  │ama-metrics│  │  │        │         │  │          │         │      │
│  │  │   pods    │  │  │  ┌─────▼──────┐  │  │          │         │      │
│  │  └───────────┘  │  │  │   AMW PE   │  │  │   Azure Bastion    │      │
│  └─────────────────┘  │  │ 10.1.2.4   │  │  └────────────────────┘      │
│                       │  └────────────┘  │                              │
│                       └──────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ Private Link
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Azure Monitor Services (PaaS)                     │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │  Azure Monitor Private Link Scope (AMPLS)                    │       │
│  │  - Ingestion: PrivateOnly                                    │       │
│  │  - Query: PrivateOnly                                        │       │
│  │                                                              │       │
│  │  ┌─────────────────────┐    ┌──────────────────────────┐     │       │
│  │  │ Log Analytics       │    │ Data Collection          │     │       │
│  │  │ Workspace           │    │ Endpoint (DCE)           │     │       │
│  │  │ (Container Insights)│    │ (Config Access)          │     │       │
│  │  └─────────────────────┘    └──────────────────────────┘     │       │
│  └──────────────────────────────────────────────────────────────┘       │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │  Azure Monitor Workspace (Prometheus)                        │       │
│  │  - Public Network Access: Disabled                           │       │
│  │  - Ingestion via Private Endpoint                            │       │
│  └──────────────────────────────────────────────────────────────┘       │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────┐       │
│  │  Data Collection Rule (DCR)                                  │       │
│  │  - Stream: Microsoft-PrometheusMetrics                       │       │
│  │  - Destination: Azure Monitor Workspace                      │       │
│  └──────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘

                    7 Private DNS Zones for Name Resolution
          ┌──────────────────────────────────────────────────────┐
          │ • privatelink.eastus2.azmk8s.io                      │
          │ • privatelink.eastus2.prometheus.monitor.azure.com   │
          │ • privatelink.monitor.azure.com                      │
          │ • privatelink.oms.opinsights.azure.com               │
          │ • privatelink.ods.opinsights.azure.com               │
          │ • privatelink.agentsvc.azure-automation.net          │
          │ • privatelink.blob.core.windows.net                  │
          └──────────────────────────────────────────────────────┘
```

## Key Components and Why They're Needed

### Private AKS Cluster
- **Standard SKU**: Required for private clusters
- **Private Cluster Enabled**: API server only accessible via private endpoint
- **Monitor Metrics Enabled**: Deploys ama-metrics pods for Prometheus scraping
- **2 Nodes (128GB OS disk)**: Sufficient resources for ama-metrics pods and system workloads

### Azure Monitor Workspace (Prometheus)
- **Public Network Access: Disabled**: Fully private ingestion
- **Private Endpoint**: Dedicated endpoint (10.1.2.4) for metrics ingestion
- **Region-Specific DNS Zone**: `privatelink.{region}.prometheus.monitor.azure.com` (critical!)

### Data Collection Endpoint (DCE)
**Purpose**: Provides the configuration endpoint for ama-metrics pods in private clusters

**Why It's Critical**:
- In private clusters, ama-metrics pods cannot reach public Azure endpoints
- The DCE must be accessible via private link for pods to retrieve their configuration
- Without DCE in AMPLS, pods fail with: `"Data collection endpoint must be used to access configuration over private link"` (403 error)

**Requirements**:
- Must be added to Azure Monitor Private Link Scope (AMPLS)
- Cannot have a dedicated private endpoint (unlike AMW)
- Accessed through the AMPLS private endpoint (10.1.2.5)

### Data Collection Rule (DCR)
**Purpose**: Defines WHAT metrics to collect and WHERE to send them

**Configuration**:
- **Data Sources**: `prometheus_metric` platform type
- **Stream**: `Microsoft-PrometheusMetrics`
- **Destinations**: Points to Azure Monitor Workspace for ingestion
- Tells ama-metrics pods what to scrape and where to send metrics

### Data Collection Rule Associations (DCRA)
**Purpose**: Links the AKS cluster to both the DCR and DCE

**Critical Pattern - Two Separate Associations Required**:

1. **DCR Association** (`demo-aks-prometheus-dcra`):
   - Links AKS cluster → Data Collection Rule
   - Defines the data collection configuration
   - Name: Can be any valid name

2. **DCE Association** (`configurationAccessEndpoint`):
   - Links AKS cluster → Data Collection Endpoint  
   - Enables configuration access via private link
   - Name: **MUST be exactly `configurationAccessEndpoint`** (Azure requirement)

**Why Both Are Required**:
- DCR association alone = pods know WHAT to collect but can't access config (403 errors)
- DCE association alone = pods can access config endpoint but don't know WHAT to collect
- Both together = pods retrieve config via private DCE and send metrics per DCR definition

**Terraform Constraint**:
```terraform
# Cannot specify both in one resource - Azure requires separate associations
data_collection_rule_id     = "..."  # OR
data_collection_endpoint_id = "..."  # But not both
```

### Azure Monitor Private Link Scope (AMPLS)
**Purpose**: Consolidates private link access for multiple Azure Monitor resources

**Scoped Resources**:
- Log Analytics Workspace (for Container Insights)
- Data Collection Endpoint (for Prometheus config access)

**Configuration**:
- **Ingestion Access Mode**: `PrivateOnly` - blocks all public ingestion
- **Query Access Mode**: `PrivateOnly` - blocks all public queries
- Single private endpoint (10.1.2.5) serves all scoped resources

### Private DNS Zones
**Critical for Name Resolution**: Without correct DNS zones, private endpoints resolve to public IPs

**Region-Specific Zones** (commonly missed):
- ❌ `privatelink.prometheus.monitor.azure.com` → **WRONG** (resolves to public IP)
- ✅ `privatelink.{region}.prometheus.monitor.azure.com` → **CORRECT** (resolves to private IP)

**All Required Zones**:
- AKS API server: `privatelink.{region}.azmk8s.io`
- Prometheus ingestion: `privatelink.{region}.prometheus.monitor.azure.com`
- AMPLS resources: `privatelink.monitor.azure.com`
- Log Analytics ingestion: `privatelink.oms.opinsights.azure.com`
- Log Analytics data: `privatelink.ods.opinsights.azure.com`
- Automation agent: `privatelink.agentsvc.azure-automation.net`
- Blob storage: `privatelink.blob.core.windows.net`

### Windows VM with Bastion
**Purpose**: Provides secure access to private resources for testing

- Access private AKS API via `az aks command invoke`
- Query Azure Monitor Workspace through private endpoint in browser
- No public IP required - accessed via Azure Bastion

## Data Flow: Metrics Collection

```
AKS Pods → ama-metrics DaemonSet → Scrape Metrics
                ↓
        Query DCE via AMPLS PE (10.1.2.5)
                ↓
        Retrieve Configuration (DCR rules)
                ↓
        Process & Filter Metrics
                ↓
        Send to AMW via Private PE (10.1.2.4)
                ↓
    Azure Monitor Workspace Storage
                ↓
        Query via Jumpbox (private access)
```

## Important Configuration Notes

### Node Pool Sizing
- **OS Disk Size**: 128GB (up from default 30GB)
  - ama-metrics pods require significant disk space
  - Avoids disk pressure evictions
- **Min Count**: 2 nodes
  - Ensures ama-metrics deployment (2 replicas) can schedule
  - Provides HA for system workloads
- **Node Pool Rotation**: Required when changing `os_disk_size_gb`
  ```terraform
  temporary_name_for_rotation = "systemtmp"
  ```

### MetricsExtension Process
The ama-metrics pods run a sidecar process called `MetricsExtension` that:
- Listens on localhost:55680 (OTLP endpoint)
- Receives scraped metrics from OpenTelemetry collector
- Forwards metrics to Azure Monitor Workspace via private endpoint

**Common Failure Scenario**:
- Missing DCE association → MetricsExtension fails to start → No listener on port 55680
- Logs show: `Error getting PID for process MetricsExtension: error running exit status 1`
- Fix: Ensure `configurationAccessEndpoint` DCRA exists

## Validation

**Check ama-metrics pods**:
```bash
az aks command invoke --name <cluster> --resource-group <rg> \
  --command "kubectl get pods -n kube-system | grep ama-metrics"
```

**Verify configuration loaded** (should NOT show "No configuration present"):
```bash
az aks command invoke --name <cluster> --resource-group <rg> \
  --command "kubectl logs -n kube-system -l rsName=ama-metrics --tail=50"
```

**Check Prometheus targets**:
```bash
az aks command invoke --name <cluster> --resource-group <rg> \
  --command "kubectl exec -n kube-system deploy/ama-metrics -c prometheus-collector -- wget -q -O- http://localhost:9090/api/v1/targets"
```

## Common Issues and Solutions

### Issue: "No configuration present for the AKS resource"
**Cause**: DCE association missing or DCE not in AMPLS  
**Solution**: 
1. Verify `configurationAccessEndpoint` DCRA exists
2. Ensure DCE is in AMPLS scoped resources
3. Restart ama-metrics pods after adding association

### Issue: Private endpoint resolves to public IP
**Cause**: Missing or incorrect DNS zone name  
**Solution**: Use region-specific DNS zones: `privatelink.{region}.prometheus.monitor.azure.com`

### Issue: 403 "Data collection endpoint must be used to access configuration over private link"
**Cause**: DCE not accessible via private link  
**Solution**: Add DCE to AMPLS as scoped resource (not a direct private endpoint)

### Issue: ama-metrics pods won't schedule
**Cause**: Insufficient node resources or disk pressure  
**Solution**: 
- Increase `min_count` to 2
- Set `os_disk_size_gb` to 128
- Use `temporary_name_for_rotation` for node pool updates

## Key Learnings

1. **Two DCRAs Required**: One for DCR (data collection rules), one for DCE (config access)
2. **DCE Must Be Named `configurationAccessEndpoint`**: This is a platform requirement
3. **DCE Goes in AMPLS, Not Direct PE**: Unlike AMW, DCEs don't support dedicated private endpoints
4. **Region-Specific DNS Zones**: Prometheus zones include region in the name
5. **Node Pool Rotation**: Required for `os_disk_size_gb` changes on existing clusters

## Resource Dependencies

```
VNet → Subnets → Private Endpoints → Private DNS Zones
                        ↓
              Azure Monitor Workspace ←── Data Collection Rule
                        ↓                           ↓
              AMPLS (contains DCE & LAW)            │
                        ↓                           │
                    AKS Cluster ←──────────────────┘
                        ↓
            Two DCRAs: DCR + DCE (configurationAccessEndpoint)
```