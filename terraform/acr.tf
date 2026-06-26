resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  # admin_enabled = false is deliberate — this repo's pattern is identity-
  # based access throughout (Workload Identity, AcrPull role assignment),
  # not shared admin credentials. Enabling the ACR admin account would
  # reintroduce a static credential this program is specifically designed
  # to avoid.
  tags = merge(var.tags, { environment = var.environment })
}