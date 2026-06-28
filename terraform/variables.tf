variable "resource_group_name" {
  description = "Name of the resource group that holds all resources for this program."
  type        = string
  default     = "rg-ai-appsec-devsecops"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "australiaeast"
}

variable "environment" {
  description = "Environment tag applied to all resources (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "aks-contoso-rag"
}

variable "aks_node_count" {
  description = "Number of nodes in the default AKS node pool. Kept small deliberately — this is a portfolio build, not a production-scale cluster."
  type        = number
  default     = 2
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes. Standard_B2s was the original choice but is not allowed in this subscription in eastus — Azure restricts available SKUs per subscription/region based on real-time capacity, and eastus is particularly constrained. Standard_D2s_v7 was confirmed available via the error message's own allow-list when Standard_B2s was rejected."
  type        = string
  default     = "Standard_D2s_v7"
}

variable "acr_name" {
  description = "Name of the Azure Container Registry. Must be globally unique, alphanumeric only."
  type        = string
  default     = "acrcontosorag"
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault. Must be globally unique."
  type        = string
  default     = "kv-contoso-rag"
}

variable "workload_identity_name" {
  description = "Name of the user-assigned managed identity used for AKS Workload Identity Federation."
  type        = string
  default     = "id-rag-api-workload"
}

variable "rag_api_namespace" {
  description = "Kubernetes namespace the RAG API runs in — must match kubernetes/pod-security.yaml."
  type        = string
  default     = "contoso-rag"
}

variable "rag_api_service_account" {
  description = "Kubernetes ServiceAccount name the RAG API runs as — must match kubernetes/rbac.yaml."
  type        = string
  default     = "rag-api-sa"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    project    = "ai-appsec-devsecops-pipeline"
    managed_by = "terraform"
  }
}

variable "github_repository" {
  description = "GitHub repository in OWNER/REPO format, used to scope the OIDC federated credential subject for CI/CD. Must exactly match the real repo — this is a case-sensitive, exact-string trust boundary, not a cosmetic label."
  type        = string
  # Deliberately no default — this must be set explicitly in
  # terraform.tfvars to the real repository path.
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing Log Analytics workspace to send AKS Container Insights logs to. Reuses the Sentinel-onboarded workspace from the companion ai-security-llm-governance-controls repo (law-ai-governance-sentinel) rather than provisioning a redundant one — both model the same fictitious Contoso Retail Group tenant."
  type        = string
}