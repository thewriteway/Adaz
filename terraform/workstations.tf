resource "azurerm_network_interface" "workstation" {
  count = length(local.domain.workstations)

  name                = "${var.prefix}-wks-${count.index}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "static"
    subnet_id                     = azurerm_subnet.workstations.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.workstations_subnet_cidr, 10 + count.index)
    public_ip_address_id          = azurerm_public_ip.workstation[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "workstation" {
  count = length(local.domain.workstations)

  network_interface_id      = azurerm_network_interface.workstation[count.index].id
  network_security_group_id = azurerm_network_security_group.windows.id
}
resource "azurerm_virtual_machine" "workstation" {
  count = length(local.domain.workstations)

  name                  = local.domain.workstations[count.index].name
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.workstation[count.index].id]
  
  boot_diagnostics {
    enabled     = "true"
    storage_uri = ""
  }
  
  vm_size               = var.workstations_vm_size

  # Delete OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Delete data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    #id = data.azurerm_image.workstation.id

    # az vm image list -f "Windows-10" --all
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    # gensecond: see https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
    sku     = "win10-22h2-pro-g2"
    version = "latest"
  }
  storage_os_disk {
    name              = "wks-${count.index}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
  os_profile {
    computer_name  = local.domain.workstations[count.index].name
    admin_username = local.accounts.ansible.username
    admin_password = local.accounts.ansible.password
  }
  os_profile_windows_config {
    provision_vm_agent = true
    enable_automatic_upgrades = true
    timezone                  = "Central European Standard Time"
    winrm {
      protocol = "HTTP"
    }
  }

  tags = {
    kind = "workstation"
  }
}

 resource "azurerm_virtual_machine_extension" "worksoft1" {
  name                 = "install-worksoft1"
   publisher            = "Microsoft.Compute"
    type                 = "CustomScriptExtension"
   virtual_machine_id = azurerm_virtual_machine.workstation[0].id
  type_handler_version = "1.10"
  settings = <<SETTINGS
           {
              "fileUris": [
                "https://raw.githubusercontent.com/ansible/ansible-documentation/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
                    ],
            "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -File ConfigureRemotingForAnsible.ps1"
        }
 SETTINGS
  depends_on = [
    azurerm_virtual_machine.workstation
    ]

  }

  resource "azurerm_virtual_machine_extension" "worksoft2" {
  name                 = "install-worksoft2"
   publisher            = "Microsoft.Compute"
    type                 = "CustomScriptExtension"
   virtual_machine_id = azurerm_virtual_machine.workstation[1].id
  type_handler_version = "1.10"
  settings = <<SETTINGS
        {
              "fileUris": [
                "https://raw.githubusercontent.com/ansible/ansible-documentation/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
                    ],
            "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -File ConfigureRemotingForAnsible.ps1"
        }
    SETTINGS
  depends_on = [
    azurerm_virtual_machine.workstation
    ]

  }

  resource "null_resource" "workstation_provision" {
  provisioner "local-exec" {
    working_dir = "${path.root}/../ansible"
    command     =  "bash -c 'source ~/Adaz/ansible/venv/bin/activate && ansible-playbook ~/Adaz/ansible/workstations.yml -v'"
  }

  # Note: the dependance on 'azurerm_virtual_machine.workstation' applies to *all* resources created from this block
  # The provisioner will only be run once all workstations have been created (not once per workstation)
  # c.f. https://github.com/hashicorp/terraform/issues/15285
  depends_on = [
    azurerm_virtual_machine.dc,
    azurerm_virtual_machine.workstation,
    azurerm_virtual_machine_extension.domsoft,
    azurerm_virtual_machine_extension.worksoft1,
    azurerm_virtual_machine_extension.worksoft2,
    null_resource.dc_provision
  ]
}
