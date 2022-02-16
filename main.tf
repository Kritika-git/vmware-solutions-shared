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
  catalog_name  = "rhcos-test" 
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
    "guestinfo.ignition.config.data"           = "ewogICJpZ25pdGlvbiI6IHsKICAgICJ2ZXJzaW9uIjogIjMuMS4wIgogIH0sCiAgInBhc3N3ZCI6IHsKICAgICJ1c2VycyI6IFsKICAgICAgewogICAgICAgICJuYW1lIjogImNvcmUiLAogICAgICAgICJwYXNzd29yZEhhc2giOiAiJHkkajlUJFpXajd0d3Fsb1M2bEYyYXloWGcvRTAkSklKbzFWMVk1MkRoangwMk9WbC54Z3NSNi93QTVacndXUkFSVXkxSWR6QSIsCiAgICAgICAgInNzaEF1dGhvcml6ZWRLZXlzIjogWyAiIiBdCiAgICAgIH0KICAgIF0KICB9LAogICJzdG9yYWdlIjogewogICAgImZpbGVzIjogWwogICAgICB7CiAgICAgICAgInBhdGgiOiAiL2V0Yy9ob3N0bmFtZSIsCiAgICAgICAgImNvbnRlbnRzIjogewogICAgICAgICAgInNvdXJjZSI6ICJkYXRhOixmY29zMDEubXlkb21haW4uaW50cmEiCiAgICAgICAgfSwKICAgICAgICAibW9kZSI6IDQyMAogICAgICB9LAogICAgICB7CiAgICAgICAgIm92ZXJ3cml0ZSI6IHRydWUsCiAgICAgICAgInBhdGgiOiAiL3Vzci9sb2NhbC9iaW4vaWJtLWhvc3QtYXR0YWNoLnNoIiwKICAgICAgICAiY29udGVudHMiOiB7CiAgICAgICAgICAic291cmNlIjogImRhdGE6dGV4dC9wbGFpbjtiYXNlNjQsSXlFdmRYTnlMMkpwYmk5bGJuWWdZbUZ6YUFwelpYUWdMV1Y0Q20xclpHbHlJQzF3SUM5bGRHTXZjMkYwWld4c2FYUmxabXhoWjNNS1NFOVRWRjlCVTFOSlIwNWZSa3hCUnowaUwyVjBZeTl6WVhSbGJHeHBkR1ZtYkdGbmN5OW9iM04wWVhSMFlXTm9abXhoWnlJS2FXWWdXMXNnTFdZZ0lpUklUMU5VWDBGVFUwbEhUbDlHVEVGSElpQmRYVHNnZEdobGJnb2dJQ0FnWldOb2J5QWlhRzl6ZENCb1lYTWdZV3h5WldGa2VTQmlaV1Z1SUdGemMybG5ibVZrTGlCdVpXVmtJSFJ2SUhKbGJHOWhaQ0JpWldadmNtVWdlVzkxSUhSeWVTQjBhR1VnWVhSMFlXTm9JR0ZuWVdsdUlnb2dJQ0FnWlhocGRDQXdDbVpwQ25ObGRDQXJlQXBJVDFOVVgxRlZSVlZGWDFSUFMwVk9QU0kyWWpRd09EQmxOekV3WVdNeE9XVXhObVZoTURSak16QTNOamt6TjJGa1lXVXlNREpsTkROaVltSmxNVEUwTlRCaVl6aGxaRGMwT0Rnek1XTm1aRFl5TlRBeFpqbGxaR0U0WXpFME9UZ3pOVGRrTWpJMk5XWmhOekV5WVRnM00ySXpPR0ZtT1dNNFpqazJZakUzT1RoaFlURTFOV0kzWVdGaVpEUTBNalZqWW1VM01XTmlPV0V5WW1Ga1pHTTVOakF4TTJNMU5HUXhNek15T1Rsak56ZGxNV0k0WlRGa1lUY3hZVEkwTldZMk56QmhaV1ZqWTJJek5HUmtORGxpWVRsak56bGpaV0kxWWprNU56RXpPVGM1WkRka1lqYzRPVFl4WkRZMVlqa3lZMk0xTW1NMU9HUmxaalUzTkRJME1EVTBPVE0zWTJFM1lXUmpOakk0Tm1JMU5HSXdaVGhsWWpoaU5HSTVZMlE1T1RrNVl6UXdNVE16WVRnek5HTTJZVEpqT1RaalptVm1aamM1TlRCa1l6QmhaV0ZqTVdJME5HWm1Nakl5WmpsaE5tWTJZV1V3TnpFek1EQmxaamN3WlRjeE9ERXpZamsxWmpFMFltUTVOekJrTUdNeE9XWTNPV1k1WlRJMU9HVTNZalprTXpnMk5qTTFZelJtWm1aaE9EVmlaVGN6WkRsaU1UVmpaVFV5TlRRME5qRTFabU01WWpBMlpXUXdOamcxWmpoalpXSTRObUV6TW1Zek1qRXlNMlJoWm1SaVlqSTNaREJsWVdSalpXVm1ZemxoTXprNFpXUm1OelV6TldGaVpqQmtOMlZtWlRsa09UWm1PV1k1TTJZMk5UUTJOMkl6TmpVeE5URXlPREUxTTJNMk56ZzRaR1ZqWVRjd01ETXlaQ0lLYzJWMElDMTRDa0ZEUTA5VlRsUmZTVVE5SW1SbE1tTTBNREpqT0Rnd1l6UTFOMlJoWVRnMFltTXlNR1EzWXpoaE1HSXpJZ3BEVDA1VVVrOU1URVZTWDBsRVBTSmpPRFZyT0RCbk1UQnZkRFp0TkRSd2NHNXJNQ0lLUVZCSlgxVlNURDBpYUhSMGNITTZMeTl2Y21sbmFXNHVZMjl1ZEdGcGJtVnljeTV3Y21WMFpYTjBMbU5zYjNWa0xtbGliUzVqYjIwdlltOXZkSE4wY21Gd0lncEJVRWxmVkVWTlVGOVZVa3c5SkNobFkyaHZJQ0lrUVZCSlgxVlNUQ0lnZkNCaGQyc2dMVVppYjI5MGMzUnlZWEFnSjN0d2NtbHVkQ0FrTVgwbktRcFNSVWRKVDA0OUluVnpMWE52ZFhSb0lnb0taWGh3YjNKMElFaFBVMVJmVVZWRlZVVmZWRTlMUlU0S1pYaHdiM0owSUVGRFEwOVZUbFJmU1VRS1pYaHdiM0owSUVOUFRsUlNUMHhNUlZKZlNVUUtaWGh3YjNKMElGSkZSMGxQVGdvamMyaDFkR1J2ZDI0Z2EyNXZkMjRnWW14aFkydHNhWE4wWldRZ2MyVnlkbWxqWlhNZ1ptOXlJRk5oZEdWc2JHbDBaU0FvZEdobGMyVWdkMmxzYkNCaWNtVmhheUJyZFdKbEtRcHpaWFFnSzJVS2MzbHpkR1Z0WTNSc0lITjBiM0FnTFdZZ2FYQjBZV0pzWlhNdWMyVnlkbWxqWlFwemVYTjBaVzFqZEd3Z1pHbHpZV0pzWlNCcGNIUmhZbXhsY3k1elpYSjJhV05sQ25ONWMzUmxiV04wYkNCdFlYTnJJR2x3ZEdGaWJHVnpMbk5sY25acFkyVUtjM2x6ZEdWdFkzUnNJSE4wYjNBZ0xXWWdabWx5WlhkaGJHeGtMbk5sY25acFkyVUtjM2x6ZEdWdFkzUnNJR1JwYzJGaWJHVWdabWx5WlhkaGJHeGtMbk5sY25acFkyVUtjM2x6ZEdWdFkzUnNJRzFoYzJzZ1ptbHlaWGRoYkd4a0xuTmxjblpwWTJVS2MyVjBJQzFsQ20xclpHbHlJQzF3SUM5bGRHTXZjMkYwWld4c2FYUmxiV0ZqYUdsdVpXbGtaMlZ1WlhKaGRHbHZiZ3BwWmlCYld5QWhJQzFtSUM5bGRHTXZjMkYwWld4c2FYUmxiV0ZqYUdsdVpXbGtaMlZ1WlhKaGRHbHZiaTl0WVdOb2FXNWxhV1JuWlc1bGNtRjBaV1FnWFYwN0lIUm9aVzRLSUNBZ0lISnRJQzFtSUM5bGRHTXZiV0ZqYUdsdVpTMXBaQW9nSUNBZ2MzbHpkR1Z0WkMxdFlXTm9hVzVsTFdsa0xYTmxkSFZ3Q2lBZ0lDQjBiM1ZqYUNBdlpYUmpMM05oZEdWc2JHbDBaVzFoWTJocGJtVnBaR2RsYm1WeVlYUnBiMjR2YldGamFHbHVaV2xrWjJWdVpYSmhkR1ZrQ21acENpTlRWRVZRSURFNklFZEJWRWhGVWlCSlRrWlBVazFCVkVsUFRpQlVTRUZVSUZkSlRFd2dRa1VnVlZORlJDQlVUeUJTUlVkSlUxUkZVaUJVU0VVZ1NFOVRWQXBOUVVOSVNVNUZYMGxFUFNRb1kyRjBJQzlsZEdNdmJXRmphR2x1WlMxcFpDa0tRMUJWVXowa0tHNXdjbTlqS1FwTlJVMVBVbGs5SkNobmNtVndJRTFsYlZSdmRHRnNJQzl3Y205akwyMWxiV2x1Wm04Z2ZDQmhkMnNnSjN0d2NtbHVkQ0FrTW4wbktRcElUMU5VVGtGTlJUMGtLR2h2YzNSdVlXMWxJQzF6S1FwSVQxTlVUa0ZOUlQwa2UwaFBVMVJPUVUxRkxDeDlDbVY0Y0c5eWRDQkRVRlZUQ21WNGNHOXlkQ0JOUlUxUFVsa0tDbk5sZENBclpRcHBaaUJuY21Wd0lDMXhhU0FpWTI5eVpXOXpJaUE4SUM5bGRHTXZjbVZrYUdGMExYSmxiR1ZoYzJVN0lIUm9aVzRLSUNCUFVFVlNRVlJKVGtkZlUxbFRWRVZOUFNKU1NFTlBVeUlLWld4cFppQm5jbVZ3SUMxeGFTQWliV0ZwY0c4aUlEd2dMMlYwWXk5eVpXUm9ZWFF0Y21Wc1pXRnpaVHNnZEdobGJnb2dJRTlRUlZKQlZFbE9SMTlUV1ZOVVJVMDlJbEpJUlV3M0lncGxiR2xtSUdkeVpYQWdMWEZwSUNKdmIzUndZU0lnUENBdlpYUmpMM0psWkdoaGRDMXlaV3hsWVhObE95QjBhR1Z1Q2lBZ1QxQkZVa0ZVU1U1SFgxTlpVMVJGVFQwaVVraEZURGdpQ21Wc2MyVUtJQ0JsWTJodklDSlBjR1Z5WVhScGJtY2dVM2x6ZEdWdElHNXZkQ0J6ZFhCd2IzSjBaV1FpQ2lBZ1QxQkZVa0ZVU1U1SFgxTlpVMVJGVFQwaVZVNUxUazlYVGlJS1pta0tjMlYwSUMxbENncGxlSEJ2Y25RZ1QxQkZVa0ZVU1U1SFgxTlpVMVJGVFFvS2FXWWdXMXNnSWlSN1QxQkZVa0ZVU1U1SFgxTlpVMVJGVFgwaUlDRTlJQ0pTU0VOUFV5SWdYVjA3SUhSb1pXNEtJQ0JsWTJodklDSlVhR2x6SUhOamNtbHdkQ0JwY3lCdmJteDVJR2x1ZEdWdVpHVmtJSFJ2SUhKMWJpQjNhWFJvSUdGdUlGSklRMDlUSUc5d1pYSmhkR2x1WnlCemVYTjBaVzB1SUVOMWNuSmxiblFnYjNCbGNtRjBhVzVuSUhONWMzUmxiU0FrZTA5UVJWSkJWRWxPUjE5VFdWTlVSVTE5SWdvZ0lHVjRhWFFnTVFwbWFRb0tVMFZNUlVOVVQxSmZURUZDUlV4VFBTUW9hbkVnTFc0Z0xTMWhjbWNnUTFCVlV5QWlKRU5RVlZNaUlDMHRZWEpuSUUxRlRVOVNXU0FpSkUxRlRVOVNXU0lnTFMxaGNtY2dUMUJGVWtGVVNVNUhYMU5aVTFSRlRTQWlKRTlRUlZKQlZFbE9SMTlUV1ZOVVJVMGlJQ2Q3Q2lBZ1kzQjFPaUFrUTFCVlV5d0tJQ0J0WlcxdmNuazZJQ1JOUlUxUFVsa3NDaUFnYjNNNklDUlBVRVZTUVZSSlRrZGZVMWxUVkVWTkNuMG5LUXB6WlhRZ0syVUtaWGh3YjNKMElGcFBUa1U5SWlJS1pXTm9ieUFpVUhKdlltbHVaeUJtYjNJZ1FWZFRJRzFsZEdGa1lYUmhJZ3BuWVhSb1pYSmZlbTl1WlY5cGJtWnZLQ2tnZXdvZ0lDQWdTRlJVVUY5U1JWTlFUMDVUUlQwa0tHTjFjbXdnTFMxM2NtbDBaUzF2ZFhRZ0lraFVWRkJUVkVGVVZWTTZKWHRvZEhSd1gyTnZaR1Y5SWlBdExXMWhlQzEwYVcxbElERXdJR2gwZEhBNkx5OHhOamt1TWpVMExqRTJPUzR5TlRRdmJHRjBaWE4wTDIxbGRHRXRaR0YwWVM5d2JHRmpaVzFsYm5RdllYWmhhV3hoWW1sc2FYUjVMWHB2Ym1VcENpQWdJQ0JJVkZSUVgxTlVRVlJWVXowa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhSeUlDMWtJQ2RjYmljZ2ZDQmhkMnNnTFVZNklDY3ZMaXBJVkZSUVUxUkJWRlZUT2loYk1DMDVYWHN6ZlNra0x5QjdJSEJ5YVc1MElDUXlJSDBuS1FvZ0lDQWdTRlJVVUY5Q1QwUlpQU1FvWldOb2J5QWlKRWhVVkZCZlVrVlRVRTlPVTBVaUlId2djMlZrSUMxRklDZHpMMGhVVkZCVFZFRlVWVk5jT2xzd0xUbGRlek45SkM4dkp5a0tJQ0FnSUdsbUlGdGJJQ0lrU0ZSVVVGOVRWRUZVVlZNaUlDMXVaU0F5TURBZ1hWMDdJSFJvWlc0S0lDQWdJQ0FnSUNCbFkyaHZJQ0ppWVdRZ2NtVjBkWEp1SUdOdlpHVWlDaUFnSUNBZ0lDQWdjbVYwZFhKdUlERUtJQ0FnSUdacENpQWdJQ0JwWmlCYld5QWlKRWhVVkZCZlFrOUVXU0lnUFg0Z1cxNWhMWHBCTFZvd0xUa3RYU0JkWFRzZ2RHaGxiZ29nSUNBZ0lDQWdJR1ZqYUc4Z0ltbHVkbUZzYVdRZ2VtOXVaU0JtYjNKdFlYUWlDaUFnSUNBZ0lDQWdjbVYwZFhKdUlERUtJQ0FnSUdacENpQWdJQ0JhVDA1RlBTSWtTRlJVVUY5Q1QwUlpJZ3A5Q21sbUlHZGhkR2hsY2w5NmIyNWxYMmx1Wm04N0lIUm9aVzRLSUNBZ0lHVmphRzhnSW1GM2N5QnRaWFJoWkdGMFlTQmtaWFJsWTNSbFpDSUtabWtLYVdZZ1cxc2dMWG9nSWlSYVQwNUZJaUJkWFRzZ2RHaGxiZ29nSUNBZ1pXTm9ieUFpWldOb2J5QlFjbTlpYVc1bklHWnZjaUJCZW5WeVpTQk5aWFJoWkdGMFlTSUtJQ0FnSUdWNGNHOXlkQ0JNVDBOQlZFbFBUbDlKVGtaUFBTSWlDaUFnSUNCbGVIQnZjblFnUVZwVlVrVmZXazlPUlY5T1ZVMUNSVkpmU1U1R1R6MGlJZ29nSUNBZ1oyRjBhR1Z5WDJ4dlkyRjBhVzl1WDJsdVptOG9LU0I3Q2lBZ0lDQWdJQ0FnU0ZSVVVGOVNSVk5RVDA1VFJUMGtLR04xY213Z0xVZ2dUV1YwWVdSaGRHRTZkSEoxWlNBdExXNXZjSEp2ZUhrZ0lpb2lJQzB0ZDNKcGRHVXRiM1YwSUNKSVZGUlFVMVJCVkZWVE9pVjdhSFIwY0Y5amIyUmxmU0lnTFMxdFlYZ3RkR2x0WlNBeE1DQWlhSFIwY0Rvdkx6RTJPUzR5TlRRdU1UWTVMakkxTkM5dFpYUmhaR0YwWVM5cGJuTjBZVzVqWlM5amIyMXdkWFJsTDJ4dlkyRjBhVzl1UDJGd2FTMTJaWEp6YVc5dVBUSXdNakV0TURFdE1ERW1abTl5YldGMFBYUmxlSFFpS1FvZ0lDQWdJQ0FnSUVoVVZGQmZVMVJCVkZWVFBTUW9aV05vYnlBaUpFaFVWRkJmVWtWVFVFOU9VMFVpSUh3Z2RISWdMV1FnSjF4dUp5QjhJR0YzYXlBdFJqb2dKeTh1S2toVVZGQlRWRUZVVlZNNktGc3dMVGxkZXpOOUtTUXZJSHNnY0hKcGJuUWdKRElnZlNjcENpQWdJQ0FnSUNBZ1NGUlVVRjlDVDBSWlBTUW9aV05vYnlBaUpFaFVWRkJmVWtWVFVFOU9VMFVpSUh3Z2MyVmtJQzFGSUNkekwwaFVWRkJUVkVGVVZWTmNPbHN3TFRsZGV6TjlKQzh2SnlrS0lDQWdJQ0FnSUNCcFppQmJXeUFpSkVoVVZGQmZVMVJCVkZWVElpQXRibVVnTWpBd0lGMWRPeUIwYUdWdUNpQWdJQ0FnSUNBZ0lDQWdJR1ZqYUc4Z0ltSmhaQ0J5WlhSMWNtNGdZMjlrWlNJS0lDQWdJQ0FnSUNBZ0lDQWdjbVYwZFhKdUlERUtJQ0FnSUNBZ0lDQm1hUW9nSUNBZ0lDQWdJR2xtSUZ0YklDSWtTRlJVVUY5Q1QwUlpJaUE5ZmlCYlhtRXRla0V0V2pBdE9TMWRJRjFkT3lCMGFHVnVDaUFnSUNBZ0lDQWdJQ0FnSUdWamFHOGdJbWx1ZG1Gc2FXUWdabTl5YldGMElnb2dJQ0FnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdNUW9nSUNBZ0lDQWdJR1pwQ2lBZ0lDQWdJQ0FnVEU5RFFWUkpUMDVmU1U1R1R6MGlKRWhVVkZCZlFrOUVXU0lLSUNBZ0lIMEtJQ0FnSUdkaGRHaGxjbDloZW5WeVpWOTZiMjVsWDI1MWJXSmxjbDlwYm1adktDa2dld29nSUNBZ0lDQWdJRWhVVkZCZlVrVlRVRTlPVTBVOUpDaGpkWEpzSUMxSUlFMWxkR0ZrWVhSaE9uUnlkV1VnTFMxdWIzQnliM2g1SUNJcUlpQXRMWGR5YVhSbExXOTFkQ0FpU0ZSVVVGTlVRVlJWVXpvbGUyaDBkSEJmWTI5a1pYMGlJQzB0YldGNExYUnBiV1VnTVRBZ0ltaDBkSEE2THk4eE5qa3VNalUwTGpFMk9TNHlOVFF2YldWMFlXUmhkR0V2YVc1emRHRnVZMlV2WTI5dGNIVjBaUzk2YjI1bFAyRndhUzEyWlhKemFXOXVQVEl3TWpFdE1ERXRNREVtWm05eWJXRjBQWFJsZUhRaUtRb2dJQ0FnSUNBZ0lFaFVWRkJmVTFSQlZGVlRQU1FvWldOb2J5QWlKRWhVVkZCZlVrVlRVRTlPVTBVaUlId2dkSElnTFdRZ0oxeHVKeUI4SUhObFpDQXRSU0FuY3k4dUtraFVWRkJUVkVGVVZWTTZLRnN3TFRsZGV6TjlLU1F2WERFdkp5a0tJQ0FnSUNBZ0lDQklWRlJRWDBKUFJGazlKQ2hsWTJodklDSWtTRlJVVUY5U1JWTlFUMDVUUlNJZ2ZDQnpaV1FnTFVVZ0ozTXZTRlJVVUZOVVFWUlZVMXc2V3pBdE9WMTdNMzBrTHk4bktRb2dJQ0FnSUNBZ0lHbG1JRnRiSUNJa1NGUlVVRjlUVkVGVVZWTWlJQzF1WlNBeU1EQWdYVjA3SUhSb1pXNEtJQ0FnSUNBZ0lDQWdJQ0FnWldOb2J5QWlZbUZrSUhKbGRIVnliaUJqYjJSbElnb2dJQ0FnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdNUW9nSUNBZ0lDQWdJR1pwQ2lBZ0lDQWdJQ0FnYVdZZ1cxc2dJaVJJVkZSUVgwSlBSRmtpSUQxK0lGdGVZUzE2UVMxYU1DMDVMVjBnWFYwN0lIUm9aVzRLSUNBZ0lDQWdJQ0FnSUNBZ1pXTm9ieUFpYVc1MllXeHBaQ0JtYjNKdFlYUWlDaUFnSUNBZ0lDQWdJQ0FnSUhKbGRIVnliaUF4Q2lBZ0lDQWdJQ0FnWm1rS0lDQWdJQ0FnSUNCQldsVlNSVjlhVDA1RlgwNVZUVUpGVWw5SlRrWlBQU0lrU0ZSVVVGOUNUMFJaSWdvZ0lDQWdmUW9nSUNBZ1oyRjBhR1Z5WDNwdmJtVmZhVzVtYnlncElIc0tJQ0FnSUNBZ0lDQnBaaUFoSUdkaGRHaGxjbDlzYjJOaGRHbHZibDlwYm1adk95QjBhR1Z1Q2lBZ0lDQWdJQ0FnSUNBZ0lISmxkSFZ5YmlBeENpQWdJQ0FnSUNBZ1pta0tJQ0FnSUNBZ0lDQnBaaUFoSUdkaGRHaGxjbDloZW5WeVpWOTZiMjVsWDI1MWJXSmxjbDlwYm1adk95QjBhR1Z1Q2lBZ0lDQWdJQ0FnSUNBZ0lISmxkSFZ5YmlBeENpQWdJQ0FnSUNBZ1pta0tJQ0FnSUNBZ0lDQnBaaUJiV3lBdGJpQWlKRUZhVlZKRlgxcFBUa1ZmVGxWTlFrVlNYMGxPUms4aUlGMWRPeUIwYUdWdUNpQWdJQ0FnSUNBZ0lDQmFUMDVGUFNJa2UweFBRMEZVU1U5T1gwbE9Sazk5TFNSN1FWcFZVa1ZmV2s5T1JWOU9WVTFDUlZKZlNVNUdUMzBpQ2lBZ0lDQWdJQ0FnWld4elpRb2dJQ0FnSUNBZ0lDQWdXazlPUlQwaUpIdE1UME5CVkVsUFRsOUpUa1pQZlNJS0lDQWdJQ0FnSUNCbWFRb2dJQ0FnZlFvZ0lDQWdhV1lnWjJGMGFHVnlYM3B2Ym1WZmFXNW1ienNnZEdobGJnb2dJQ0FnSUNBZ0lHVmphRzhnSW1GNmRYSmxJRzFsZEdGa1lYUmhJR1JsZEdWamRHVmtJZ29nSUNBZ1pta0tabWtLYVdZZ1cxc2dMWG9nSWlSYVQwNUZJaUJkWFRzZ2RHaGxiZ29nSUNBZ1pXTm9ieUFpWldOb2J5QlFjbTlpYVc1bklHWnZjaUJIUTBVZ1RXVjBZV1JoZEdFaUNpQWdJQ0JuWVhSb1pYSmZlbTl1WlY5cGJtWnZLQ2tnZXdvZ0lDQWdJQ0FnSUVoVVZGQmZVa1ZUVUU5T1UwVTlKQ2hqZFhKc0lDMHRkM0pwZEdVdGIzVjBJQ0pJVkZSUVUxUkJWRlZUT2lWN2FIUjBjRjlqYjJSbGZTSWdMUzF0WVhndGRHbHRaU0F4TUNBaWFIUjBjRG92TDIxbGRHRmtZWFJoTG1kdmIyZHNaUzVwYm5SbGNtNWhiQzlqYjIxd2RYUmxUV1YwWVdSaGRHRXZkakV2YVc1emRHRnVZMlV2ZW05dVpTSWdMVWdnSWsxbGRHRmtZWFJoTFVac1lYWnZjam9nUjI5dloyeGxJaWtLSUNBZ0lDQWdJQ0JJVkZSUVgxTlVRVlJWVXowa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhSeUlDMWtJQ2RjYmljZ2ZDQnpaV1FnTFVVZ0ozTXZMaXBJVkZSUVUxUkJWRlZUT2loYk1DMDVYWHN6ZlNra0wxd3hMeWNwQ2lBZ0lDQWdJQ0FnU0ZSVVVGOUNUMFJaUFNRb1pXTm9ieUFpSkVoVVZGQmZVa1ZUVUU5T1UwVWlJSHdnYzJWa0lDMUZJQ2R6TDBoVVZGQlRWRUZVVlZOY09sc3dMVGxkZXpOOUpDOHZKeWtLSUNBZ0lDQWdJQ0JwWmlCYld5QWlKRWhVVkZCZlUxUkJWRlZUSWlBdGJtVWdNakF3SUYxZE95QjBhR1Z1Q2lBZ0lDQWdJQ0FnSUNBZ0lHVmphRzhnSW1KaFpDQnlaWFIxY200Z1kyOWtaU0lLSUNBZ0lDQWdJQ0FnSUNBZ2NtVjBkWEp1SURFS0lDQWdJQ0FnSUNCbWFRb2dJQ0FnSUNBZ0lGQlBWRVZPVkVsQlRGOWFUMDVGWDFKRlUxQlBUbE5GUFNRb1pXTm9ieUFpSkVoVVZGQmZRazlFV1NJZ2ZDQmhkMnNnTFVZZ0p5OG5JQ2Q3Y0hKcGJuUWdKRTVHZlNjcENpQWdJQ0FnSUNBZ2FXWWdXMXNnSWlSUVQxUkZUbFJKUVV4ZldrOU9SVjlTUlZOUVQwNVRSU0lnUFg0Z1cxNWhMWHBCTFZvd0xUa3RYU0JkWFRzZ2RHaGxiZ29nSUNBZ0lDQWdJQ0FnSUNCbFkyaHZJQ0pwYm5aaGJHbGtJSHB2Ym1VZ1ptOXliV0YwSWdvZ0lDQWdJQ0FnSUNBZ0lDQnlaWFIxY200Z01Rb2dJQ0FnSUNBZ0lHWnBDaUFnSUNBZ0lDQWdXazlPUlQwaUpGQlBWRVZPVkVsQlRGOWFUMDVGWDFKRlUxQlBUbE5GSWdvZ0lDQWdmUW9nSUNBZ2FXWWdaMkYwYUdWeVgzcHZibVZmYVc1bWJ6c2dkR2hsYmdvZ0lDQWdJQ0FnSUdWamFHOGdJbWRqWlNCdFpYUmhaR0YwWVNCa1pYUmxZM1JsWkNJS0lDQWdJR1pwQ21acENuTmxkQ0F0WlFwcFppQmJXeUF0YmlBaUpGcFBUa1VpSUYxZE95QjBhR1Z1Q2lBZ1UwVk1SVU5VVDFKZlRFRkNSVXhUUFNRb2FuRWdMVzRnTFMxaGNtY2dRMUJWVXlBaUpFTlFWVk1pSUMwdFlYSm5JRTFGVFU5U1dTQWlKRTFGVFU5U1dTSWdMUzFoY21jZ1QxQkZVa0ZVU1U1SFgxTlpVMVJGVFNBaUpFOVFSVkpCVkVsT1IxOVRXVk5VUlUwaUlDMHRZWEpuSUZwUFRrVWdJaVJhVDA1RklpQW5ld29nSUdOd2RUb2dKRU5RVlZNc0NpQWdiV1Z0YjNKNU9pQWtUVVZOVDFKWkxBb2dJRzl6T2lBa1QxQkZVa0ZVU1U1SFgxTlpVMVJGVFN3S0lDQjZiMjVsT2lBa1drOU9SUXA5SnlrS1pta0taV05vYnlBaUpIdFRSVXhGUTFSUFVsOU1RVUpGVEZOOUlpQStJQzkwYlhBdlpHVjBaV04wWldSelpXeGxZM1J2Y214aFltVnNjd29LYVdZZ1d5QXRaaUFpTDNSdGNDOXdjbTkyYVdSbFpITmxiR1ZqZEc5eWJHRmlaV3h6SWlCZE95QjBhR1Z1Q2lBZ1UwVk1SVU5VVDFKZlRFRkNSVXhUUFNJa0tHcHhJQzF6SUNjdVd6QmRJQ29nTGxzeFhTY2dMM1J0Y0M5a1pYUmxZM1JsWkhObGJHVmpkRzl5YkdGaVpXeHpJQzkwYlhBdmNISnZkbWxrWldSelpXeGxZM1J2Y214aFltVnNjeWtpQ21Wc2MyVUtJQ0JUUlV4RlExUlBVbDlNUVVKRlRGTTlKQ2hxY1NBdUlDOTBiWEF2WkdWMFpXTjBaV1J6Wld4bFkzUnZjbXhoWW1Wc2N5a0tabWtLQ2lOVGRHVndJREk2SUZORlZGVlFJRTFGVkVGRVFWUkJDbU5oZENBOFBFVlBSaUErTDNSdGNDOXlaV2RwYzNSbGNpNXFjMjl1Q25zS0ltTnZiblJ5YjJ4c1pYSWlPaUFpSkVOUFRsUlNUMHhNUlZKZlNVUWlMQW9pYm1GdFpTSTZJQ0lrU0U5VFZFNUJUVVVpTEFvaWFXUmxiblJwWm1sbGNpSTZJQ0lrVFVGRFNFbE9SVjlKUkNJc0NpSnNZV0psYkhNaU9pQWtVMFZNUlVOVVQxSmZURUZDUlV4VENuMEtSVTlHQ25ObGRDQXJaUW9qZEhKNUlIUnZJR1J2ZDI1c2IyRmtJR0Z1WkNCeWRXNGdhRzl6ZENCb1pXRnNkR2dnWTJobFkyc2djMk55YVhCMENuTmxkQ0FyZUFvalptbHljM1FnZEhKNUlIUnZJSFJvWlNCellYUmxiR3hwZEdVdGFHVmhiSFJvSUhObGNuWnBZMlVnYVhNZ1pXNWhZbXhsWkFwSVZGUlFYMUpGVTFCUFRsTkZQU1FvWTNWeWJDQXRMWGR5YVhSbExXOTFkQ0FpU0ZSVVVGTlVRVlJWVXpvbGUyaDBkSEJmWTI5a1pYMGlJQzB0Y21WMGNua2dOU0F0TFhKbGRISjVMV1JsYkdGNUlERXdJQzB0Y21WMGNua3RiV0Y0TFhScGJXVWdOakFnWEFvZ0lDQWdJQ0FnSUNJa2UwRlFTVjlWVWt4OWMyRjBaV3hzYVhSbExXaGxZV3gwYUM5aGNHa3ZkakV2YUdWc2JHOGlLUXB6WlhRZ0xYZ0tTRlJVVUY5Q1QwUlpQU1FvWldOb2J5QWlKRWhVVkZCZlVrVlRVRTlPVTBVaUlId2djMlZrSUMxRklDZHpMMGhVVkZCVFZFRlVWVk5jT2xzd0xUbGRlek45SkM4dkp5a0tTRlJVVUY5VFZFRlVWVk05SkNobFkyaHZJQ0lrU0ZSVVVGOVNSVk5RVDA1VFJTSWdmQ0IwY2lBdFpDQW5YRzRuSUh3Z2MyVmtJQzFGSUNkekx5NHFTRlJVVUZOVVFWUlZVem9vV3pBdE9WMTdNMzBwSkM5Y01TOG5LUXBsWTJodklDSWtTRlJVVUY5VFZFRlVWVk1pQ21sbUlGdGJJQ0lrU0ZSVVVGOVRWRUZVVlZNaUlDMWxjU0F5TURBZ1hWMDdJSFJvWlc0S0lDQWdJQ0FnSUNCelpYUWdLM2dLSUNBZ0lDQWdJQ0JJVkZSUVgxSkZVMUJQVGxORlBTUW9ZM1Z5YkNBdExYZHlhWFJsTFc5MWRDQWlTRlJVVUZOVVFWUlZVem9sZTJoMGRIQmZZMjlrWlgwaUlDMHRjbVYwY25rZ01qQWdMUzF5WlhSeWVTMWtaV3hoZVNBeE1DQXRMWEpsZEhKNUxXMWhlQzEwYVcxbElETTJNQ0JjQ2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FpSkh0QlVFbGZWVkpNZlhOaGRHVnNiR2wwWlMxb1pXRnNkR2d2YzJGMExXaHZjM1F0WTJobFkyc2lJQzF2SUM5MWMzSXZiRzlqWVd3dlltbHVMM05oZEMxb2IzTjBMV05vWldOcktRb2dJQ0FnSUNBZ0lITmxkQ0F0ZUFvZ0lDQWdJQ0FnSUVoVVZGQmZRazlFV1Qwa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhObFpDQXRSU0FuY3k5SVZGUlFVMVJCVkZWVFhEcGJNQzA1WFhzemZTUXZMeWNwQ2lBZ0lDQWdJQ0FnU0ZSVVVGOVRWRUZVVlZNOUpDaGxZMmh2SUNJa1NGUlVVRjlTUlZOUVQwNVRSU0lnZkNCMGNpQXRaQ0FuWEc0bklId2dZWGRySUMxR09pQW5MeTRxU0ZSVVVGTlVRVlJWVXpvb1d6QXRPVjE3TTMwcEpDOGdleUJ3Y21sdWRDQWtNaUI5SnlrS0lDQWdJQ0FnSUNCbFkyaHZJQ0lrU0ZSVVVGOUNUMFJaSWdvZ0lDQWdJQ0FnSUdWamFHOGdJaVJJVkZSUVgxTlVRVlJWVXlJS0lDQWdJQ0FnSUNCcFppQmJXeUFpSkVoVVZGQmZVMVJCVkZWVElpQXRaWEVnTWpBd0lGMWRPeUIwYUdWdUNpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCamFHMXZaQ0FyZUNBdmRYTnlMMnh2WTJGc0wySnBiaTl6WVhRdGFHOXpkQzFqYUdWamF3b2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ2MyVjBJQ3Q0Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0IwYVcxbGIzVjBJRFZ0SUM5MWMzSXZiRzlqWVd3dlltbHVMM05oZEMxb2IzTjBMV05vWldOcklDMHRjbVZuYVc5dUlDUlNSVWRKVDA0Z0xTMWxibVJ3YjJsdWRDQWtRVkJKWDFWU1RBb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ2MyVjBJQzE0Q2lBZ0lDQWdJQ0FnWld4elpRb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ1pXTm9ieUFpUlhKeWIzSWdaRzkzYm14dllXUnBibWNnYUc5emRDQm9aV0ZzZEdnZ1kyaGxZMnNnYzJOeWFYQjBJRnRJVkZSUUlITjBZWFIxY3pvZ0pFaFVWRkJmVTFSQlZGVlRYU0lLSUNBZ0lDQWdJQ0JtYVFwbGJITmxDaUFnSUNBZ0lDQWdaV05vYnlBaVUydHBjSEJwYm1jZ1pHOTNibXh2WVdScGJtY2dhRzl6ZENCb1pXRnNkR2dnWTJobFkyc2djMk55YVhCMElGdElWRlJRSUhOMFlYUjFjem9nSkVoVVZGQmZVMVJCVkZWVFhTSUtabWtLYzJWMElDMWxDbk5sZENBcmVBb2pVMVJGVUNBek9pQlNSVWRKVTFSRlVpQklUMU5VSUZSUElGUklSU0JJVDFOVVVWVkZWVVV1SUU1RlJVUWdWRThnUlZaQlRGVkJWRVVnU0ZSVVVDQlRWRUZVVlZNZ05EQTVJRVZZU1ZOVVV5d2dNakF4SUdOeVpXRjBaV1F1SUVGTVRDQlBWRWhGVWxNZ1JrRkpUQzRLU0ZSVVVGOVNSVk5RVDA1VFJUMGtLR04xY213Z0xTMTNjbWwwWlMxdmRYUWdJa2hVVkZCVFZFRlVWVk02Slh0b2RIUndYMk52WkdWOUlpQXRMWEpsZEhKNUlERXdNQ0F0TFhKbGRISjVMV1JsYkdGNUlERXdJQzB0Y21WMGNua3RiV0Y0TFhScGJXVWdNVGd3TUNBdFdDQlFUMU5VSUZ3S0lDQWdJQzFJSUNKWUxVRjFkR2d0U0c5emRIRjFaWFZsTFVGUVNVdGxlVG9nSkVoUFUxUmZVVlZGVlVWZlZFOUxSVTRpSUZ3S0lDQWdJQzFJSUNKWUxVRjFkR2d0U0c5emRIRjFaWFZsTFVGalkyOTFiblE2SUNSQlEwTlBWVTVVWDBsRUlpQmNDaUFnSUNBdFNDQWlRMjl1ZEdWdWRDMVVlWEJsT2lCaGNIQnNhV05oZEdsdmJpOXFjMjl1SWlCY0NpQWdJQ0F0WkNCQUwzUnRjQzl5WldkcGMzUmxjaTVxYzI5dUlGd0tJQ0FnSUNJa2UwRlFTVjlVUlUxUVgxVlNUSDEyTWk5dGRXeDBhWE5vYVdaMEwyaHZjM1J4ZFdWMVpTOW9iM04wTDNKbFoybHpkR1Z5SWlrS2MyVjBJQzE0Q2toVVZGQmZRazlFV1Qwa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhObFpDQXRSU0FuY3k5SVZGUlFVMVJCVkZWVFhEcGJNQzA1WFhzemZTUXZMeWNwQ2toVVZGQmZVMVJCVkZWVFBTUW9aV05vYnlBaUpFaFVWRkJmVWtWVFVFOU9VMFVpSUh3Z2RISWdMV1FnSjF4dUp5QjhJSE5sWkNBdFJTQW5jeTh1S2toVVZGQlRWRUZVVlZNNktGc3dMVGxkZXpOOUtTUXZYREV2SnlrS1pXTm9ieUFpSkVoVVZGQmZRazlFV1NJS1pXTm9ieUFpSkVoVVZGQmZVMVJCVkZWVElncHBaaUJiV3lBaUpFaFVWRkJmVTFSQlZGVlRJaUF0Ym1VZ01qQXhJRjFkT3lCMGFHVnVDaUFnSUNCbFkyaHZJQ0pGY25KdmNpQmJTRlJVVUNCemRHRjBkWE02SUNSSVZGUlFYMU5VUVZSVlUxMGlDaUFnSUNCbGVHbDBJREVLWm1rS0kxTlVSVkFnTkRvZ1YwRkpWQ0JHVDFJZ1RVVk5Ra1ZTVTBoSlVDQlVUeUJDUlNCQlUxTkpSMDVGUkFwSVQxTlVYMGxFUFNRb1pXTm9ieUFpSkVoVVZGQmZRazlFV1NJZ2ZDQnFjU0F0Y2lBbkxtbGtKeWtLZDJocGJHVWdkSEoxWlRzZ1pHOEtJQ0FnSUhObGRDQXJaWGdLSUNBZ0lFRlRVMGxIVGsxRlRsUTlKQ2hqZFhKc0lDMHRjbVYwY25rZ01UQXdJQzB0Y21WMGNua3RaR1ZzWVhrZ01UQWdMUzF5WlhSeWVTMXRZWGd0ZEdsdFpTQXhPREF3SUZ3S0lDQWdJQ0FnSUNBdFNDQWlXQzFCZFhSb0xVaHZjM1J4ZFdWMVpTMUJVRWxMWlhrNklDUklUMU5VWDFGVlJWVkZYMVJQUzBWT0lpQmNDaUFnSUNBZ0lDQWdMVWdnSWtOdmJuUmxiblF0Vkhsd1pUb2dZWEJ3YkdsallYUnBiMjR2ZUMxM2QzY3RabTl5YlMxMWNteGxibU52WkdWa0lpQmNDaUFnSUNBZ0lDQWdMUzFrWVhSaExYVnliR1Z1WTI5a1pTQm9iM04wYVdROUlpUklUMU5VWDBsRUlpQmNDaUFnSUNBZ0lDQWdMUzFrWVhSaExYVnliR1Z1WTI5a1pTQnNiMk5oZEdsdmJtbGtQU0lrUTA5T1ZGSlBURXhGVWw5SlJDSWdYQW9nSUNBZ0lDQWdJQzB0WkdGMFlTMTFjbXhsYm1OdlpHVWdZV05qYjNWdWRHbGtQU0lrUVVORFQxVk9WRjlKUkNJZ1hBb2dJQ0FnSUNBZ0lDSWtlMEZRU1Y5VlVreDlMM05oZEdWc2JHbDBaUzloYzNOcFoyNGlLUW9nSUNBZ2MyVjBJQzFsZUFvZ0lDQWdhWE5CYzNOcFoyNWxaRDBrS0dWamFHOGdJaVJCVTFOSlIwNU5SVTVVSWlCOElHcHhJQzF5SUNjdWFYTkJjM05wWjI1bFpDY2dmQ0JoZDJzZ0ozdHdjbWx1ZENCMGIyeHZkMlZ5S0NRd0tYMG5LUW9nSUNBZ2FXWWdXMXNnSWlScGMwRnpjMmxuYm1Wa0lpQTlQU0FpZEhKMVpTSWdYVjA3SUhSb1pXNEtJQ0FnSUNBZ0lDQmljbVZoYXdvZ0lDQWdabWtLSUNBZ0lHbG1JRnRiSUNJa2FYTkJjM05wWjI1bFpDSWdJVDBnSW1aaGJITmxJaUJkWFRzZ2RHaGxiZ29nSUNBZ0lDQWdJR1ZqYUc4Z0luVnVaWGh3WldOMFpXUWdkbUZzZFdVZ1ptOXlJR0Z6YzJsbmJpQnlaWFJ5ZVdsdVp5SUtJQ0FnSUdacENpQWdJQ0J6YkdWbGNDQXhNQXBrYjI1bENtVjRjRzl5ZENCSVQxTlVYMGxFQ2lOVFZFVlFJRFU2SUVGVFUwbEhUazFGVGxRZ1NFRlRJRUpGUlU0Z1RVRkVSUzRnVTBGV1JTQlRRMUpKVUZRZ1FVNUVJRkpWVGdwbFkyaHZJQ0lrUVZOVFNVZE9UVVZPVkNJZ2ZDQnFjU0F0Y2lBbkxuTmpjbWx3ZENjZ1BpOTFjM0l2Ykc5allXd3ZZbWx1TDJsaWJTMW9iM04wTFdGblpXNTBMbk5vQ2tGVFUwbEhUazFGVGxSZlNVUTlKQ2hsWTJodklDSWtRVk5UU1VkT1RVVk9WQ0lnZkNCcWNTQXRjaUFuTG1sa0p5a0tZMkYwSUR3OFJVOUdJRDR2WlhSakwzTmhkR1ZzYkdsMFpXWnNZV2R6TDJsaWJTMW9iM04wTFdGblpXNTBMWFpoY25NS1pYaHdiM0owSUVoUFUxUmZTVVE5Skh0SVQxTlVYMGxFZlFwbGVIQnZjblFnUVZOVFNVZE9UVVZPVkY5SlJEMGtlMEZUVTBsSFRrMUZUbFJmU1VSOUNrVlBSZ3BqYUcxdlpDQXdOakF3SUM5bGRHTXZjMkYwWld4c2FYUmxabXhoWjNNdmFXSnRMV2h2YzNRdFlXZGxiblF0ZG1GeWN3cGphRzF2WkNBd056QXdJQzkxYzNJdmJHOWpZV3d2WW1sdUwybGliUzFvYjNOMExXRm5aVzUwTG5Ob0NtTmhkQ0E4UEVWUFJpQStMMlYwWXk5emVYTjBaVzFrTDNONWMzUmxiUzlwWW0wdGFHOXpkQzFoWjJWdWRDNXpaWEoyYVdObENsdFZibWwwWFFwRVpYTmpjbWx3ZEdsdmJqMUpRazBnU0c5emRDQkJaMlZ1ZENCVFpYSjJhV05sQ2tGbWRHVnlQVzVsZEhkdmNtc3VkR0Z5WjJWMENsdFRaWEoyYVdObFhRcEZiblpwY205dWJXVnVkRDBpVUVGVVNEMHZkWE55TDJ4dlkyRnNMM05pYVc0NkwzVnpjaTlzYjJOaGJDOWlhVzQ2TDNWemNpOXpZbWx1T2k5MWMzSXZZbWx1T2k5elltbHVPaTlpYVc0aUNrVjRaV05UZEdGeWREMHZkWE55TDJ4dlkyRnNMMkpwYmk5cFltMHRhRzl6ZEMxaFoyVnVkQzV6YUFwU1pYTjBZWEowUFc5dUxXWmhhV3gxY21VS1VtVnpkR0Z5ZEZObFl6MDFDbHRKYm5OMFlXeHNYUXBYWVc1MFpXUkNlVDF0ZFd4MGFTMTFjMlZ5TG5SaGNtZGxkQXBGVDBZS1kyaHRiMlFnTURZME5DQXZaWFJqTDNONWMzUmxiV1F2YzNsemRHVnRMMmxpYlMxb2IzTjBMV0ZuWlc1MExuTmxjblpwWTJVS2MzbHpkR1Z0WTNSc0lHUmhaVzF2YmkxeVpXeHZZV1FLYzNsemRHVnRZM1JzSUhOMFlYSjBJR2xpYlMxb2IzTjBMV0ZuWlc1MExuTmxjblpwWTJVS2RHOTFZMmdnSWlSSVQxTlVYMEZUVTBsSFRsOUdURUZISWdvPSIKICAgICAgICB9LAogICAgICAgICJtb2RlIjogNDkzCiAgICAgIH0KICAgIF0KICB9LAogICJzeXN0ZW1kIjogewogICAgInVuaXRzIjogWwogICAgICAgIHsKICAgICAgICAiY29udGVudHMiOiAiW1VuaXRdXG5EZXNjcmlwdGlvbj1JbnN0YWxsIHBhY2thZ2VzXG5Db25kaXRpb25GaXJzdEJvb3Q9eWVzXG5XYW50cz1uZXR3b3JrLW9ubGluZS50YXJnZXRcbkFmdGVyPW5ldHdvcmstb25saW5lLnRhcmdldFxuQWZ0ZXI9bXVsdGktdXNlci50YXJnZXRcbltTZXJ2aWNlXVxuVHlwZT1vbmVzaG90XG5FeGVjU3RhcnQ9cnBtLW9zdHJlZSBpbnN0YWxsIG5hbm8gZ2l0IGRvY2tlci1jb21wb3NlIGh0b3AgLS1yZWJvb3RcbltJbnN0YWxsXVxuV2FudGVkQnk9bXVsdGktdXNlci50YXJnZXRcbiIsCiAgICAgICAgImVuYWJsZWQiOiB0cnVlLAogICAgICAgICJuYW1lIjogImluc3RhbGwtcnBtcy5zZXJ2aWNlIgogICAgICB9LAogICAgICB7CiAgICAgICAgImNvbnRlbnRzIjogIltVbml0XVxuRGVzY3JpcHRpb249SUJNIEhvc3QgQXR0YWNoIFNlcnZpY2VcbldhbnRzPW5ldHdvcmstb25saW5lLnRhcmdldFxuQWZ0ZXI9bmV0d29yay1vbmxpbmUudGFyZ2V0XG5cbltTZXJ2aWNlXVxuRW52aXJvbm1lbnQ9XCJQQVRIPS91c3IvbG9jYWwvc2JpbjovdXNyL2xvY2FsL2JpbjovdXNyL3NiaW46L3Vzci9iaW46L3NiaW46L2JpblwiXG5cbkV4ZWNTdGFydD0vdXNyL2xvY2FsL2Jpbi9pYm0taG9zdC1hdHRhY2guc2hcblJlc3RhcnQ9b24tZmFpbHVyZVxuUmVzdGFydFNlYz01XG5cbltJbnN0YWxsXVxuV2FudGVkQnk9bXVsdGktdXNlci50YXJnZXRcblxuXG4iLAogICAgICAgICJlbmFibGVkIjogdHJ1ZSwKICAgICAgICAibmFtZSI6ICJpYm0taG9zdC1hdHRhY2guc2VydmljZSIKICAgICAgfQogICAgXQogIH0KfQ=="
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
