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
  name          = "vm-fedora-latest-test"
  catalog_name  = ""rhcos-test" 
  template_name = "fedora-coreos"
  memory        = 16384
  cpus          = 4
  
  network {
    type               = "org"
    name               = vcd_vapp_org_network.tutorial_network.org_network_name
    ip_allocation_mode = "POOL"
    is_primary         = true
  }
  guest_properties = {
    "guestinfo.ignition.config.data"           = "ewogICJpZ25pdGlvbiI6IHsKICAgICJ2ZXJzaW9uIjogIjMuMS4wIgogIH0sCiAgInBhc3N3ZCI6IHsKICAgICJ1c2VycyI6IFsKICAgICAgewogICAgICAgICJuYW1lIjogImNvcmUiLAogICAgICAgICJwYXNzd29yZEhhc2giOiAiJHkkajlUJFpXajd0d3Fsb1M2bEYyYXloWGcvRTAkSklKbzFWMVk1MkRoangwMk9WbC54Z3NSNi93QTVacndXUkFSVXkxSWR6QSIsCiAgICAgICAgInNzaEF1dGhvcml6ZWRLZXlzIjogWyAic3NoLXJzYSBBQUFBQjNOemFDMXljMkVBQUFBREFRQUJBQUFDQVFDNmt2QWwxeDltYWxxTExnaWZtSUdSQzlibXMyS09BbXNYL0RXZVNhTUxJUGIzK0ZEb3lCK21jcWNGVG1BUjRxVU4rQXFtS2E4YmpzUEw3bmd5dHN4T25Mayt3S2ZueXpjVkhwaEZpcG1Ya1NkRTFCRHRVQU4xNXhabWd6NHlrTW1ySU9qaTQvM3ppZzZRWHZ0TmFHMnlGUUpqZHBTR3RQR2h5QlNtS2xFS05vZVdVQWZpWHYrMGk4MEt6ZjlLa1l2dVZuRUVMVFdIa1pOaitQSW0zbjU0SVhBMFBHOTRvL2trYlpxNC9lcTFMcHlGWlZ6TEJuME5VTXg0dTFOZk5IR0VaV3RuYnlpWWEwMnlFTXFZN3pvRHlDRDlyT0l3UnExajRZT3E0QTEwTVVUekV6MFArWlRyZXZONW1vOVNnd3lwL050enkwNk54NERrWFhVc1c5V1dYYVdFWEE1Z2FvWEk3ZUp2UmJxVTFlcjl2WWxSSmMxaWdNUkpQWDc0TlVSUHVTcnlSS3VMbHZldWpLWHVubkhjeGwzdjY1UU9lWkZydlRaWjdHYWFxT0VlcVJLZ1JTUDQ4L0dVYU5BcU5xemNVT0RRWGhSSDRlRFRaaVRVS1JFVXRHOEh6eHFGOW84M09PQ09tNGFMMjUrdjBXempvYjBjeFVKQ01ObHhxQUJQUk96enMvSmJZRER5bXJoOGFheEtieXJoYmZTdWtNd3VnbnNpVjROR0ZuNWZ5SUNkK3IxR3F1VkwxdTRkempaajdpWkhMa1hzSXdCaVEvVTg4enpNMEtXelNGZjQ2OVkyS1JFZ2Q0YmJVaW5hWTU3MXVDVVdQR0NLYjhYQU9GL05LdTRSVHJXMVVERUpDbTN2ZDRUblY1S1RLK2ozYWt6Mks1ZmZDT3dzU3c9PSBzdXJpbmVlZGlzYXR5YWJoYXJnYXZpQFN1cmluZWVkaXMtTWFjQm9vay1Qcm8ubG9jYWwiIF0KICAgICAgfQogICAgXQogIH0sCiAgInN0b3JhZ2UiOiB7CiAgICAiZmlsZXMiOiBbCiAgICAgICAgewogICAgICAgICJwYXRoIjogIi9ldGMvaG9zdG5hbWUiLAogICAgICAgICJjb250ZW50cyI6IHsKICAgICAgICAgICJzb3VyY2UiOiAiZGF0YTosZmNvczAyLm15ZG9tYWluLmludHJhIgogICAgICAgIH0sCiAgICAgICAgIm1vZGUiOiA0MjAKICAgICAgfSwKICAgICAgewogICAgICAgICJwYXRoIjogIi9ldGMvTmV0d29ya01hbmFnZXIvc3lzdGVtLWNvbm5lY3Rpb25zL2VuczIubm1jb25uZWN0aW9uIiwKICAgICAgICAiY29udGVudHMiOiB7CiAgICAgICAgICAic291cmNlIjogImRhdGE6LCU1QmNvbm5lY3Rpb24lNUQlMEFpZCUzRGVuczE5MiUwQXR5cGUlM0RldGhlcm5ldCUwQWludGVyZmFjZS1uYW1lJTNEZW5zMTkyJTBBJTVCaXB2NCU1RCUwQWFkZHJlc3MxJTNEMTkyLjE2OC4xMDAuNSUyRjI0JTJDMTkyLjE2OC4xMDAuMSUwQWRoY3AtaG9zdG5hbWUlM0RmY29zMDEubXlkb21haW4uaW50cmElMEFkbnMlM0Q5LjkuOS45JTNCJTBBZG5zLXNlYXJjaCUzRCUwQW1heS1mYWlsJTNEZmFsc2UlMEFtZXRob2QlM0RtYW51YWwlMEEiCiAgICAgICAgfSwKICAgICAgICAibW9kZSI6IDM4NAogICAgICB9LAogICAgICB7CiAgICAgICAgInBhdGgiOiAiL2V0Yy9zeXN0ZW1kL3pyYW0tZ2VuZXJhdG9yLmNvbmYiLAogICAgICAgICJjb250ZW50cyI6IHsKICAgICAgICAgICJzb3VyY2UiOiAiZGF0YTo7YmFzZTY0LEl5QlVhR2x6SUdOdmJtWnBaeUJtYVd4bElHVnVZV0pzWlhNZ1lTQXZaR1YyTDNweVlXMHdJR1JsZG1salpTQjNhWFJvSUhSb1pTQmtaV1poZFd4MElITmxkSFJwYm1kekNsdDZjbUZ0TUYwSyIKICAgICAgICB9LAogICAgICAgICJtb2RlIjogNDIwCiAgICAgIH0KICAgIF0KICB9Cn0="
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
