data "azurerm_container_registry" "jmeter_acr" {
  name                = var.JMETER_ACR_NAME
  resource_group_name = var.JMETER_ACR_RESOURCE_GROUP_NAME
}

resource "random_id" "random" {
  byte_length = 4
}

resource "azurerm_resource_group" "jmeter_rg" {
  name     = var.RESOURCE_GROUP_NAME
  location = var.LOCATION
}

resource "azurerm_virtual_network" "jmeter_vnet" {
  name                = "${var.PREFIX}vnet"
  location            = azurerm_resource_group.jmeter_rg.location
  resource_group_name = azurerm_resource_group.jmeter_rg.name
  address_space       = ["${var.VNET_ADDRESS_SPACE}"]
}

resource "azurerm_subnet" "jmeter_subnet" {
  name                 = "${var.PREFIX}subnet"
  resource_group_name  = azurerm_resource_group.jmeter_rg.name
  virtual_network_name = azurerm_virtual_network.jmeter_vnet.name
  address_prefixes     = ["${var.SUBNET_ADDRESS_PREFIX}"]

  delegation {
    name = "delegation"

    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]
}

resource "azurerm_network_profile" "jmeter_net_profile" {
  name                = "${var.PREFIX}netprofile"
  location            = azurerm_resource_group.jmeter_rg.location
  resource_group_name = azurerm_resource_group.jmeter_rg.name

  container_network_interface {
    name = "${var.PREFIX}cnic"

    ip_configuration {
      name      = "${var.PREFIX}ipconfig"
      subnet_id = azurerm_subnet.jmeter_subnet.id
    }
  }
}

resource "azurerm_storage_account" "jmeter_storage" {
  name                = "${var.PREFIX}storage${random_id.random.hex}"
  resource_group_name = azurerm_resource_group.jmeter_rg.name
  location            = azurerm_resource_group.jmeter_rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  network_rules {
    default_action             = "Allow"
    virtual_network_subnet_ids = ["${azurerm_subnet.jmeter_subnet.id}"]
  }
}

resource "azurerm_storage_share" "jmeter_share" {
  name                 = "jmeter"
  storage_account_name = azurerm_storage_account.jmeter_storage.name
  quota                = var.JMETER_STORAGE_QUOTA_GIGABYTES
}

resource "azurerm_container_group" "jmeter_workers" {
  count               = var.JMETER_WORKERS_COUNT
  name                = "${var.PREFIX}-worker${count.index}"
  location            = azurerm_resource_group.jmeter_rg.location
  resource_group_name = azurerm_resource_group.jmeter_rg.name

  ip_address_type = "private"
  os_type         = "Linux"

  network_profile_id = azurerm_network_profile.jmeter_net_profile.id

  restart_policy = "Never"

  image_registry_credential {
    server   = data.azurerm_container_registry.jmeter_acr.login_server
    username = data.azurerm_container_registry.jmeter_acr.admin_username
    password = data.azurerm_container_registry.jmeter_acr.admin_password
  }

  container {
    name   = "jmeter"
    image  = var.JMETER_DOCKER_IMAGE
    cpu    = var.JMETER_WORKER_CPU
    memory = var.JMETER_WORKER_MEMORY

    ports {
      port     = var.JMETER_DOCKER_PORT
      protocol = "TCP"
    }

    environment_variables = {
      CONF_EXEC_IS_SLAVE                     = "true"
      CONF_EXEC_WORKER_COUNT                 = var.JMETER_WORKERS_COUNT
      CONF_EXEC_WORKER_NUMBER                = "${count.index}"
      JMETER_EXIT                            = "true"
      JMETER_JMX                             = var.JMETER_JMX_FILE
      JMETER_LOG_FILE                        = "jmeter-${count.index}.log"
      PROJECT_PATH                           = "/shared/project"
      OUTPUT_PATH                            = "/shared/out"
      JMETER_JVM_ARGS                        = var.JMETER_JVM_ARGS
      JMETER_PROPERTIES_FILES                = var.JMETER_PROPERTIES_FILES
      CONF_CSV_DIVIDED_TO_OUT                = var.JMETER_CONF_CSV_DIVIDED_TO_OUT
      CONF_CSV_WITH_HEADER                   = var.JMETER_CONF_CSV_WITH_HEADER
      CONF_CSV_SPLIT_PATTERN                 = var.JMETER_CONF_CSV_SPLIT_PATTERN
      CONF_CSV_SPLIT                         = var.JMETER_CONF_CSV_SPLIT
      CONF_EXEC_TIMEOUT                      = var.JMETER_CONF_EXEC_TIMEOUT
      CONF_COPY_TO_WORKSPACE                 = var.JMETER_CONF_COPY_TO_WORKSPACE
      JMETER_PLUGINS_MANAGER_INSTALL_FOR_JMX = var.JMETER_PLUGINS_MANAGER_INSTALL_FOR_JMX
      JMETER_PLUGINS_MANAGER_INSTALL_LIST    = var.JMETER_PLUGINS_MANAGER_INSTALL_LIST


    }



    volume {
      name                 = "shared"
      mount_path           = "/shared"
      read_only            = false
      storage_account_name = azurerm_storage_account.jmeter_storage.name
      storage_account_key  = azurerm_storage_account.jmeter_storage.primary_access_key
      share_name           = azurerm_storage_share.jmeter_share.name
    }

    commands = [
      "/bin/sh",
      "-c",
      "ls -laR $PROJECT_PATH ; entrypoint.sh -Jserver.rmi.ssl.disable=true  -Djava.rmi.server.hostname=$(ifconfig eth0 | grep 'inet addr:' | awk '{gsub(\"addr:\", \"\"); print $2}')  ${var.JMETER_EXTRA_CLI_ARGUMENTS} ${var.JMETER_PIPELINE_CLI_ARGUMENTS}",
    ]


  }
  tags = {
    app  = "jmeter"
    mode = "worker"
  }
}

resource "azurerm_container_group" "jmeter_controller" {
  name                = "${var.PREFIX}-controller"
  location            = azurerm_resource_group.jmeter_rg.location
  resource_group_name = azurerm_resource_group.jmeter_rg.name

  ip_address_type = "private"
  os_type         = "Linux"

  network_profile_id = azurerm_network_profile.jmeter_net_profile.id

  restart_policy = "Never"

  image_registry_credential {
    server   = data.azurerm_container_registry.jmeter_acr.login_server
    username = data.azurerm_container_registry.jmeter_acr.admin_username
    password = data.azurerm_container_registry.jmeter_acr.admin_password
  }

  container {
    name   = "jmeter"
    image  = var.JMETER_DOCKER_IMAGE
    cpu    = var.JMETER_CONTROLLER_CPU
    memory = var.JMETER_CONTROLLER_MEMORY

    ports {
      port     = var.JMETER_DOCKER_PORT
      protocol = "TCP"
    }
    environment_variables = {
      CONF_EXEC_IS_SLAVE                     = "false"
      JMETER_EXIT                            = "true"
      JMETER_JMX                             = var.JMETER_JMX_FILE
      JMETER_JTL_FILE                        = var.JMETER_RESULTS_FILE
      JMETER_LOG_FILE                        = "jmeter.log"
      JMETER_REPORT_NAME                     = var.JMETER_DASHBOARD_FOLDER
      PROJECT_PATH                           = "/shared/project"
      OUTPUT_PATH                            = "/shared/out"
      JMETER_JVM_ARGS                        = var.JMETER_JVM_ARGS
      JMETER_PROPERTIES_FILES                = var.JMETER_PROPERTIES_FILES
      CONF_EXEC_TIMEOUT                      = var.JMETER_CONF_EXEC_TIMEOUT
      CONF_COPY_TO_WORKSPACE                 = var.JMETER_CONF_COPY_TO_WORKSPACE
      JMETER_PLUGINS_MANAGER_INSTALL_FOR_JMX = var.JMETER_PLUGINS_MANAGER_INSTALL_FOR_JMX
      JMETER_PLUGINS_MANAGER_INSTALL_LIST    = var.JMETER_PLUGINS_MANAGER_INSTALL_LIST
    }

    volume {
      name                 = "shared"
      mount_path           = "/shared"
      read_only            = false
      storage_account_name = azurerm_storage_account.jmeter_storage.name
      storage_account_key  = azurerm_storage_account.jmeter_storage.primary_access_key
      share_name           = azurerm_storage_share.jmeter_share.name
    }


    commands = [
      "/bin/sh",
      "-c",
      "ls -laR $PROJECT_PATH ; entrypoint.sh -Jserver.rmi.ssl.disable=true  -Djava.rmi.server.hostname=$(ifconfig eth0 | grep 'inet addr:' | awk '{gsub(\"addr:\", \"\"); print $2}') -R ${join(",", "${azurerm_container_group.jmeter_workers.*.ip_address}")} ${var.JMETER_EXTRA_CLI_ARGUMENTS} ${var.JMETER_PIPELINE_CLI_ARGUMENTS}",
    ]
  }
  tags = {
    app  = "jmeter"
    mode = "controller"
  }
}
