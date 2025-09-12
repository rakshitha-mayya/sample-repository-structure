import base64
import pulumi
from pulumi import Output, ResourceOptions
import pulumi_azure_native as azure
import pulumi_kubernetes as k8s
from pulumi_kubernetes.helm.v3 import Chart as HelmChart, ChartOpts as HelmChartOpts, FetchOpts as HelmFetchOpts
import pulumi_azuread as azuread
import pulumi_azure as azclassic  
from pulumi import runtime
# classic used only for RBAC role assignments by name

cfg = pulumi.Config()
client_cfg = azuread.get_client_config()

def none_if_empty(v):
    if v is None:
        return None
    v = str(v).strip()
    return v if v else None

# -------- Config ("variables") --------
location            = cfg.get("location") or "East US"
resource_group_name = cfg.require("resourceGroupName")
aks_name            = cfg.require("aksClusterName")
dns_prefix          = cfg.get("dnsPrefix") or "az-pulumi-cluster"

node_count          = int(cfg.get("nodeCount") or 1)
node_vm_size        = cfg.get("nodeVmSize") or "Standard_DS2_v2"
node_rg_name_cfg    = none_if_empty(cfg.get("nodeResourceGroup")) or "mc-resource-group-pulumi"

k8s_version         = cfg.get("kubernetesVersion")
tenant_id           = cfg.require("tenantId")
subscription_id     = cfg.get("subscriptionId")

department          = cfg.get("department") or "delivery"
owner               = cfg.get("owner") or "example@kyndryl.com"
extra_tags          = cfg.get_object("defaultTags") or {}

acr_name            = cfg.require("acrName")
kv_name             = cfg.require("keyVaultName")
grafana_name        = (cfg.get("grafanaName") or "pulumi-grafana-new")  # keep <= 23 chars

# Tags (lowercase to avoid case collisions)
normalized_extra_tags = {str(k).lower(): v for k, v in (extra_tags or {}).items()}
common_tags = {"department": department, "owner": owner}
common_tags.update(normalized_extra_tags)

# -------- Resource Group --------
rg = azure.resources.ResourceGroup(
    "rg",
    resource_group_name=resource_group_name,   # <-- use config instead of hardcoding
    location=location,                         # <-- use config instead of hardcoding
    tags=common_tags,
)

# -------- Log Analytics Workspace --------
law = azure.operationalinsights.Workspace(
    "aks-logs",
    resource_group_name=rg.name,
    location=rg.location,
    workspace_name=f"{aks_name}-logs",
    retention_in_days=30,
    sku=azure.operationalinsights.WorkspaceSkuArgs(name="PerGB2018"),
    tags=common_tags,
)

# -------- AKS inputs --------
agent_pool = azure.containerservice.ManagedClusterAgentPoolProfileArgs(
    name="systempool",                # must match ^[a-z][a-z0-9]{0,11}$
    count=node_count,
    vm_size=node_vm_size,
    mode="System",
    type="VirtualMachineScaleSets",
    os_type="Linux",
)

addon_profiles = {
    "omsagent": azure.containerservice.ManagedClusterAddonProfileArgs(
        enabled=True,
        config={"logAnalyticsWorkspaceResourceID": law.id},
    )
}

aad_profile = azure.containerservice.ManagedClusterAADProfileArgs(
    enable_azure_rbac=True,
    managed=True,
    tenant_id=tenant_id,
)

identity = azure.containerservice.ManagedClusterIdentityArgs(type="SystemAssigned")

mc_args = dict(
    resource_group_name=rg.name,
    location=rg.location,
    dns_prefix=dns_prefix,
    agent_pool_profiles=[agent_pool],
    addon_profiles=addon_profiles,
    aad_profile=aad_profile,
    enable_rbac=True,
    identity=identity,
    node_resource_group=node_rg_name_cfg,
    tags=common_tags,
)
if k8s_version:
    mc_args["kubernetes_version"] = k8s_version

# -------- AKS Cluster (CREATE THIS BEFORE referencing 'aks') --------
aks = azure.containerservice.ManagedCluster(
    aks_name,
    **mc_args,
    name=aks_name,
    opts=ResourceOptions(depends_on=[rg]),
)
# aks = azure.containerservice.ManagedCluster(
#     aks_name,                    # 👈 this is the Azure AKS name (no suffix if you set it explicitly)
#     resource_group_name=rg.name,
#     location=rg.location,
#     dns_prefix=dns_prefix,
#     agent_pool_profiles=[agent_pool],
#     addon_profiles=addon_profiles,
#     aad_profile=aad_profile,
#     enable_rbac=True,
#     identity=identity,
#     node_resource_group=node_rg_name_cfg,
#     tags=common_tags,
#     **({"kubernetes_version": k8s_version} if k8s_version else {}),
#     opts=ResourceOptions(depends_on=[rg]),
# )

# -------- ACR --------
acr = azure.containerregistry.Registry(
    "acr",
    resource_group_name=rg.name,
    location=rg.location,
    registry_name=acr_name,
    sku=azure.containerregistry.SkuArgs(name="Standard"),
    admin_user_enabled=True,
    tags=common_tags,
    opts=ResourceOptions(depends_on=[rg]),
)

# -------- RBAC that needs AKS (place after AKS) --------
# Allow AKS kubelet to pull from ACR
kubelet_oid = aks.identity_profile.apply(
    lambda p: p.get("kubeletidentity").object_id if p and p.get("kubeletidentity") else None
)

acr_pull = azclassic.authorization.Assignment(
    "aks-acr-pull",
    scope=acr.id,
    role_definition_name="AcrPull",
    principal_id=kubelet_oid,
    opts=ResourceOptions(depends_on=[acr, aks]),
)

# Allow your user to push/pull from ACR
acr_push_user = azclassic.authorization.Assignment(
    "user-acr-push",
    scope=acr.id,
    role_definition_name="AcrPush",
    principal_id=client_cfg.object_id,
)

# -------- Key Vault (RBAC) + roles --------
kv = azure.keyvault.Vault(
    "kv",
    resource_group_name=rg.name,
    location=rg.location,
    vault_name=kv_name,
    properties=azure.keyvault.VaultPropertiesArgs(
        tenant_id=tenant_id,
        enable_rbac_authorization=True,
        sku=azure.keyvault.SkuArgs(name="standard", family="A"),
        enable_purge_protection=True,
        soft_delete_retention_in_days=7,
    ),
    tags=common_tags,
    opts=ResourceOptions(depends_on=[rg]),
)

kv_admin_user = azclassic.authorization.Assignment(
    "kv-admin-user",
    scope=kv.id,
    role_definition_name="Key Vault Administrator",
    principal_id=client_cfg.object_id,
)

kv_secrets_user = azclassic.authorization.Assignment(
    "kv-secrets-user",
    scope=kv.id,
    role_definition_name="Key Vault Secrets User",
    principal_id=aks.identity.principal_id,
)

# -------- Managed Grafana + Admin --------
mg = azure.dashboard.Grafana(
    "grafana",  # Pulumi logical name (can be anything)
    resource_group_name=rg.name,
    location=rg.location,
    workspace_name=grafana_name,  # <= 23 chars; uses your config name exactly
    sku=azure.dashboard.ResourceSkuArgs(name="Standard"),
    identity=azure.dashboard.ManagedServiceIdentityArgs(type="SystemAssigned"),
    tags=common_tags,
    opts=ResourceOptions(depends_on=[rg]),
)

grafana_admin = azclassic.authorization.Assignment(
    "grafana-admin",
    scope=mg.id,
    role_definition_name="Grafana Admin",
    principal_id=client_cfg.object_id,
)

# -------- Kubeconfig (AFTER AKS) --------
admin_creds = azure.containerservice.list_managed_cluster_admin_credentials_output(
    resource_group_name=rg.name,
    resource_name=aks.name,
)
kubeconfig = admin_creds.kubeconfigs[0].value.apply(lambda enc: base64.b64decode(enc).decode())

# ---------- Argo CD (Helm) + optional Application bootstrap ----------
# Config knobs (all optional; sensible defaults below)
argocd_namespace     = cfg.get("argocdNamespace") or "argocd"
argocd_chart_version = none_if_empty(cfg.get("argocdChartVersion"))  # e.g., "7.7.5" (or None for latest)

# Optional Git bootstrap (set these if you want to auto-create an Argo Application)
argo_repo_url        = none_if_empty(cfg.get("argoRepoUrl"))         # e.g., "https://github.com/org/repo.git"
argo_repo_path       = none_if_empty(cfg.get("argoRepoPath"))        # e.g., "envs/dev" or "apps"
argo_repo_revision   = none_if_empty(cfg.get("argoRepoRevision")) or "HEAD"  # branch/tag/commit
argo_app_name        = none_if_empty(cfg.get("argoAppName")) or "bootstrap"
argo_app_namespace   = none_if_empty(cfg.get("argoAppNamespace")) or argocd_namespace
argo_project_name    = none_if_empty(cfg.get("argoProjectName")) or "default"
argo_auto_sync       = cfg.get_bool("argoAutoSync") or True
argo_create_ns       = cfg.get_bool("argoCreateNamespace") or True

# Kubernetes provider for this AKS cluster
k8s_provider = k8s.Provider("k8s-aks", kubeconfig=kubeconfig, opts=ResourceOptions(depends_on=[aks]))

# Namespace for Argo CD
argocd_ns = k8s.core.v1.Namespace(
    "argocd-ns",
    metadata={"name": argocd_namespace},
    opts=ResourceOptions(provider=k8s_provider, depends_on=[aks]),
)

# Install Argo CD via Helm (server type: LoadBalancer)
argocd_values = {
    "fullnameOverride": "argocd",      # <<< pin resource names to `argocd-*`
    "server": {
        "service": {"type": "LoadBalancer"},
    }
}

argocd_chart = k8s.helm.v3.Chart(
    "argocd",
    k8s.helm.v3.ChartOpts(
        chart="argo-cd",
        version=argocd_chart_version,  # None == latest
        namespace=argocd_namespace,
        fetch_opts=k8s.helm.v3.FetchOpts(repo="https://argoproj.github.io/argo-helm"),
        values=argocd_values,
    ),
    opts=ResourceOptions(
        provider=k8s_provider,
        depends_on=[argocd_ns],  # ensure namespace exists first
    ),
)
def _server_name_from_values(values: dict) -> str:
    fo = values.get("fullnameOverride")
    return f"{fo}-server" if fo else "argocd-argocd-server"

server_svc_name = _server_name_from_values(argocd_values)

if runtime.is_dry_run():
    # During preview, avoid trying to read the Service before Helm creates it
    argocd_host = pulumi.Output.secret("pending (preview)")
else:
    # Read the Service directly from the cluster (no reliance on Helm’s internal keys)
    argocd_svc = k8s.core.v1.Service.get(
        "argocd-server-svc",
        pulumi.Output.concat(argocd_namespace, "/", server_svc_name),
        opts=ResourceOptions(provider=k8s_provider, depends_on=[argocd_chart]),
    )

    argocd_lb_ing = argocd_svc.status.apply(
        lambda s: (getattr(s, "load_balancer", None) and
                   getattr(s.load_balancer, "ingress", None) and
                   len(s.load_balancer.ingress) > 0 and
                   s.load_balancer.ingress[0]) or None
    )
    argocd_host = argocd_lb_ing.apply(lambda i: (getattr(i, "hostname", None) or getattr(i, "ip", None)))

pulumi.export("argocdNamespace", argocd_namespace)
pulumi.export("argocdServerExternal", argocd_host)

# Surface the Argo CD Server LB endpoint (hostname or IP)

# Optional: create an Argo CD Application to bootstrap workloads
# if argo_repo_url and argo_repo_path:
#     # Ensure CRDs from the chart are present before creating CRs
#     # Using depends_on=[argocd_chart] guarantees Applications are created after Helm finishes
#     app_spec = {
#         "project": argo_project_name,
#         "source": {
#             "repoURL": argo_repo_url,
#             "path": argo_repo_path,
#             "targetRevision": argo_repo_revision,
#             # If using Helm or Kustomize, add under "helm": {...} or "kustomize": {...}
#         },
#         "destination": {
#             "server": "https://kubernetes.default.svc",
#             "namespace": argo_app_namespace,
#         },
#         "syncPolicy": {
#             "automated": {"prune": True, "selfHeal": True} if argo_auto_sync else None,
#             "syncOptions": [
#                 "CreateNamespace=true" if argo_create_ns else "CreateNamespace=false"
#             ],
#         },
#     }

#     # Remove None-valued fields (CRD validation doesn’t like them)
#     def _strip_nones(obj):
#         if isinstance(obj, dict):
#             return {k: _strip_nones(v) for k, v in obj.items() if v is not None}
#         if isinstance(obj, list):
#             return [_strip_nones(v) for v in obj if v is not None]
#         return obj

#     app_spec = _strip_nones(app_spec)

#     argo_app = k8s.apiextensions.CustomResource(
#         "argocd-bootstrap-app",
#         api_version="argoproj.io/v1alpha1",
#         kind="Application",
#         metadata={
#             "name": argo_app_name,
#             "namespace": argocd_namespace,
#             "finalizers": ["resources-finalizer.argocd.argoproj.io"],
#         },
#         spec=app_spec,
#         opts=ResourceOptions(provider=k8s_provider, depends_on=[argocd_chart]),
#     )

# Export the external endpoint
pulumi.export("argocdNamespace", argocd_namespace)
pulumi.export("argocdServerExternal", argocd_host)



# -------- Optional: AKS RBAC Cluster Admin for you --------
aks_cluster_admin = azclassic.authorization.Assignment(
    "aks-cluster-admin",
    scope=aks.id,
    role_definition_name="Azure Kubernetes Service RBAC Cluster Admin",
    principal_id=client_cfg.object_id,
    opts=ResourceOptions(depends_on=[aks]),
)

# -------- Outputs --------
pulumi.export("resourceGroupName", rg.name)
pulumi.export("aksClusterName", aks.name)
pulumi.export("kubeconfig", pulumi.Output.secret(kubeconfig))

