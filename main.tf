# Configure the VMware vCloud Director Provider
provider "vcd" {
  user     = var.vcd_user
  password = var.vcd_password
  org      = var.vcd_org
  url      = var.vcd_url
  vdc      = var.vdc_name
}

# Used to obtain information from the already deployed Edge Gateway
module ibm_vmware_solutions_shared_instance {
  source = "./modules/ibm-vmware-solutions-shared-instance/"

  vdc_edge_gateway_name = var.vdc_edge_gateway_name
}

# Create a routed network
resource "vcd_network_routed" "tutorial_network" {

  name         = "Tutorial-Network"
  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  gateway      = "192.168.100.1"

  interface_type = "distributed"

  static_ip_pool {
    start_address = "192.168.100.5"
    end_address   = "192.168.100.254"
  }

  dns1 = "9.9.9.9"
  dns2 = "1.1.1.1"
}

# Create the firewall rule to access the Internet 
resource "vcd_nsxv_firewall_rule" "rule_internet" {
  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  name         = "${vcd_network_routed.tutorial_network.name}-Internet"

  action = "accept"

  source {
    org_networks = [vcd_network_routed.tutorial_network.name]
  }

  destination {
    ip_addresses = []
  }

  service {
    protocol = "any"
  }
}

# Create SNAT rule to access the Internet
resource "vcd_nsxv_snat" "rule_internet" {
  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  network_type = "ext"
  network_name = module.ibm_vmware_solutions_shared_instance.external_network_name_2

  original_address   = "${vcd_network_routed.tutorial_network.gateway}/24"
  translated_address = module.ibm_vmware_solutions_shared_instance.default_external_network_ip
}

# Create the firewall rule to allow SSH from the Internet
resource "vcd_nsxv_firewall_rule" "rule_internet_ssh" {
  count = tobool(var.allow_ssh) == true ? 1 :0

  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  name         = "${vcd_network_routed.tutorial_network.name}-Internet-SSH"

  action = "accept"

  source {
    ip_addresses = []
  }

  destination {
    ip_addresses = [module.ibm_vmware_solutions_shared_instance.default_external_network_ip]
  }

  service {
    protocol = "tcp"
    port     = 22
  }
}

# Create DNAT rule to allow SSH from the Internet
resource "vcd_nsxv_dnat" "rule_internet_ssh" {
  count = tobool(var.allow_ssh) == true ? 1 :0

  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  network_type = "ext"
  network_name = module.ibm_vmware_solutions_shared_instance.external_network_name_2

  original_address = module.ibm_vmware_solutions_shared_instance.default_external_network_ip
  original_port    = 22

  translated_address = vcd_vapp_vm.vm_1.network[0].ip
  translated_port    = 22
  protocol           = "tcp"
}

# Create the firewall to access IBM Cloud services over the IBM Cloud private network 
resource "vcd_nsxv_firewall_rule" "rule_ibm_private" {
  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  name         = "${vcd_network_routed.tutorial_network.name}-IBM-Private"

  logging_enabled = "false"
  action          = "accept"

  source {
    org_networks = [vcd_network_routed.tutorial_network.name]
  }

  destination {
    gateway_interfaces = [module.ibm_vmware_solutions_shared_instance.external_network_name_1]
  }

  service {
    protocol = "any"
  }
}

# Create SNAT rule to access the IBM Cloud services over a private network
resource "vcd_nsxv_snat" "rule_ibm_private" {
  edge_gateway = module.ibm_vmware_solutions_shared_instance.edge_gateway_name
  network_type = "ext"
  network_name = module.ibm_vmware_solutions_shared_instance.external_network_name_1

  original_address   = "${vcd_network_routed.tutorial_network.gateway}/24"
  translated_address = module.ibm_vmware_solutions_shared_instance.external_network_ips_2
}

# Create vcd App
resource "vcd_vapp" "vmware_tutorial_vapp" {
  name = "vmware-tutorial-vApp"
}

# Connect org Network to vcpApp
resource "vcd_vapp_org_network" "tutorial_network" {
  vapp_name        = vcd_vapp.vmware_tutorial_vapp.name
  org_network_name = vcd_network_routed.tutorial_network.name
}
# Create VM
resource "vcd_vapp_vm" "vm_1" {
  vapp_name     = vcd_vapp.vmware_tutorial_vapp.name
  name          = "vm-rhcos-latest-test"
  catalog_name  = "Public Catalog" 
  template_name = "rhcos OpenShift 4.8.14"
  memory        = 16384
  cpus          = 4
  
  network {
    type               = "org"
    name               = vcd_vapp_org_network.tutorial_network.org_network_name
    ip_allocation_mode = "POOL"
    is_primary         = true
  }
  guest_properties = {
    "guestinfo.ignition.config.data"           = "ewoJImlnbml0aW9uIjogewoJCSJ2ZXJzaW9uIjogIjMuMi4wIgoJfSwKCSJwYXNzd2QiOiB7CgkJInVzZXJzIjogW3sKCQkJIm5hbWUiOiAiY29yZSIsCgkJCSJwYXNzd29yZEhhc2giOiAiJDJhJDA0JDF3ZVFpTkFReE1WNEp1SnAwbmxoT3VtQUs0SzMvQ3pmYVdyTEVzZFkyVmZjVXNSd0JpNjdHIgoJCX1dCgl9LAogICJzdG9yYWdlIjogewogICAgImZpbGVzIjogWwogICAgICB7CiAgICAgICAgInBhdGgiOiAiL2V0Yy9zeXNjb25maWcvbmV0d29yay1zY3JpcHRzL2lmY2ZnLWVuczE5MiIsCiAgICAgICAgIm1vZGUiOiA0MjAsCiAgICAgICAgImNvbnRlbnRzIjogewogICAgICAgICAgInNvdXJjZSI6ICJkYXRhOnRleHQvcGxhaW47Y2hhcnNldD11dGYtODtiYXNlNjQsVkZsUVJUMUZkR2hsY201bGRBcE9RVTFGUFNKbGJuTXhPVElpQ2tSRlZrbERSVDBpWlc1ek1Ua3lJZ3BQVGtKUFQxUTllV1Z6Q2s1RlZFSlBUMVE5ZVdWekNrSlBUMVJRVWs5VVR6MXViMjVsQ2tsUVFVUkVVajBpTVRreUxqRTJPQzR4TURBdU5TSUtUa1ZVVFVGVFN6MGlNalUxTGpJMU5TNHlOVFV1TWpRd0lncEhRVlJGVjBGWlBTSXhPVEl1TVRZNExqRXdNQzR4SWdwRVRsTXhQU0k1TGprdU9TNDVJZz09IgogICAgICAgIH0KICAgICAgfQogICAgXQogIH0KfQ=="
    "guestinfo.ignition.config.data.encoding"  = "base64"
  } 

  customization {
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = "test"
    # Other customization options to override the ones from template
  }
  power_on      = true
}
