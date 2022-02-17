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
    "guestinfo.ignition.config.data"           = "ewogICJpZ25pdGlvbiI6IHsKICAgICJ2ZXJzaW9uIjogIjMuMS4wIgogIH0sCiAgInBhc3N3ZCI6IHsKICAgICJ1c2VycyI6IFsKICAgICAgewogICAgICAgICJuYW1lIjogImNvcmUiLAogICAgICAgICJwYXNzd29yZEhhc2giOiAiJHkkajlUJFpXajd0d3Fsb1M2bEYyYXloWGcvRTAkSklKbzFWMVk1MkRoangwMk9WbC54Z3NSNi93QTVacndXUkFSVXkxSWR6QSIsCiAgICAgICAgInNzaEF1dGhvcml6ZWRLZXlzIjogWyAic3NoLXJzYSBBQUFBQjNOemFDMXljMkVBQUFBREFRQUJBQUFDQVFDNmt2QWwxeDltYWxxTExnaWZtSUdSQzlibXMyS09BbXNYL0RXZVNhTUxJUGIzK0ZEb3lCK21jcWNGVG1BUjRxVU4rQXFtS2E4YmpzUEw3bmd5dHN4T25Mayt3S2ZueXpjVkhwaEZpcG1Ya1NkRTFCRHRVQU4xNXhabWd6NHlrTW1ySU9qaTQvM3ppZzZRWHZ0TmFHMnlGUUpqZHBTR3RQR2h5QlNtS2xFS05vZVdVQWZpWHYrMGk4MEt6ZjlLa1l2dVZuRUVMVFdIa1pOaitQSW0zbjU0SVhBMFBHOTRvL2trYlpxNC9lcTFMcHlGWlZ6TEJuME5VTXg0dTFOZk5IR0VaV3RuYnlpWWEwMnlFTXFZN3pvRHlDRDlyT0l3UnExajRZT3E0QTEwTVVUekV6MFArWlRyZXZONW1vOVNnd3lwL050enkwNk54NERrWFhVc1c5V1dYYVdFWEE1Z2FvWEk3ZUp2UmJxVTFlcjl2WWxSSmMxaWdNUkpQWDc0TlVSUHVTcnlSS3VMbHZldWpLWHVubkhjeGwzdjY1UU9lWkZydlRaWjdHYWFxT0VlcVJLZ1JTUDQ4L0dVYU5BcU5xemNVT0RRWGhSSDRlRFRaaVRVS1JFVXRHOEh6eHFGOW84M09PQ09tNGFMMjUrdjBXempvYjBjeFVKQ01ObHhxQUJQUk96enMvSmJZRER5bXJoOGFheEtieXJoYmZTdWtNd3VnbnNpVjROR0ZuNWZ5SUNkK3IxR3F1VkwxdTRkempaajdpWkhMa1hzSXdCaVEvVTg4enpNMEtXelNGZjQ2OVkyS1JFZ2Q0YmJVaW5hWTU3MXVDVVdQR0NLYjhYQU9GL05LdTRSVHJXMVVERUpDbTN2ZDRUblY1S1RLK2ozYWt6Mks1ZmZDT3dzU3c9PSBzdXJpbmVlZGlzYXR5YWJoYXJnYXZpQFN1cmluZWVkaXMtTWFjQm9vay1Qcm8ubG9jYWwiIF0KICAgICAgfQogICAgXQogIH0sCiAgInN0b3JhZ2UiOiB7CiAgICAiZmlsZXMiOiBbCiAgICAgICAgewogICAgICAgICJwYXRoIjogIi9ldGMvaG9zdG5hbWUiLAogICAgICAgICJjb250ZW50cyI6IHsKICAgICAgICAgICJzb3VyY2UiOiAiZGF0YTosZmNvczAxLm15ZG9tYWluLmludHJhIgogICAgICAgIH0sCiAgICAgICAgIm1vZGUiOiA0MjAKICAgICAgfSwKICAgICAgewogICAgICAgICJwYXRoIjogIi9ldGMvTmV0d29ya01hbmFnZXIvc3lzdGVtLWNvbm5lY3Rpb25zL2VuczIubm1jb25uZWN0aW9uIiwKICAgICAgICAiY29udGVudHMiOiB7CiAgICAgICAgICAic291cmNlIjogImRhdGE6LCU1QmNvbm5lY3Rpb24lNUQlMEFpZCUzRGVuczE5MiUwQXR5cGUlM0RldGhlcm5ldCUwQWludGVyZmFjZS1uYW1lJTNEZW5zMTkyJTBBJTVCaXB2NCU1RCUwQWFkZHJlc3MxJTNEMTkyLjE2OC4xMDAuNSUyRjI0JTJDMTkyLjE2OC4xMDAuMSUwQWRoY3AtaG9zdG5hbWUlM0RmY29zMDEubXlkb21haW4uaW50cmElMEFkbnMlM0Q5LjkuOS45JTNCJTBBZG5zLXNlYXJjaCUzRCUwQW1heS1mYWlsJTNEZmFsc2UlMEFtZXRob2QlM0RtYW51YWwlMEEiCiAgICAgICAgfSwKICAgICAgICAibW9kZSI6IDM4NAogICAgICB9LAogICAgICB7CiAgICAgICAgInBhdGgiOiAiL2V0Yy9zeXN0ZW1kL3pyYW0tZ2VuZXJhdG9yLmNvbmYiLAogICAgICAgICJjb250ZW50cyI6IHsKICAgICAgICAgICJzb3VyY2UiOiAiZGF0YTo7YmFzZTY0LEl5QlVhR2x6SUdOdmJtWnBaeUJtYVd4bElHVnVZV0pzWlhNZ1lTQXZaR1YyTDNweVlXMHdJR1JsZG1salpTQjNhWFJvSUhSb1pTQmtaV1poZFd4MElITmxkSFJwYm1kekNsdDZjbUZ0TUYwSyIKICAgICAgICB9LAogICAgICAgICJtb2RlIjogNDIwCiAgICAgIH0sCiAgICAgIHsKICAgICAgICAib3ZlcndyaXRlIjogdHJ1ZSwKICAgICAgICAicGF0aCI6ICIvdXNyL2xvY2FsL2Jpbi9pYm0taG9zdC1hdHRhY2guc2giLAogICAgICAgICJjb250ZW50cyI6IHsKICAgICAgICAgICJzb3VyY2UiOiAiZGF0YTp0ZXh0L3BsYWluO2Jhc2U2NCxJeUV2ZFhOeUwySnBiaTlsYm5ZZ1ltRnphQXB6WlhRZ0xXVjRDbTFyWkdseUlDMXdJQzlsZEdNdmMyRjBaV3hzYVhSbFpteGhaM01LU0U5VFZGOUJVMU5KUjA1ZlJreEJSejBpTDJWMFl5OXpZWFJsYkd4cGRHVm1iR0ZuY3k5b2IzTjBZWFIwWVdOb1pteGhaeUlLYVdZZ1cxc2dMV1lnSWlSSVQxTlVYMEZUVTBsSFRsOUdURUZISWlCZFhUc2dkR2hsYmdvZ0lDQWdaV05vYnlBaWFHOXpkQ0JvWVhNZ1lXeHlaV0ZrZVNCaVpXVnVJR0Z6YzJsbmJtVmtMaUJ1WldWa0lIUnZJSEpsYkc5aFpDQmlaV1p2Y21VZ2VXOTFJSFJ5ZVNCMGFHVWdZWFIwWVdOb0lHRm5ZV2x1SWdvZ0lDQWdaWGhwZENBd0NtWnBDbk5sZENBcmVBcElUMU5VWDFGVlJWVkZYMVJQUzBWT1BTSmpORGhtTnpRd1kyUmhOV0ZoWVRVNE1EQXlNVEJtWldSaU9HWXpOalU1WTJGbU5HSmtZakJoTUROak5USm1NVE5tTW1Gak5UTTRaR015WWpreU9UazFNakl6WldNNU56UXdNamM1TVRSak1USTNaalF5TVRZMFpHSTJZV00yT1RNNU9ERXhNR1l6WXpSa00yWXdaRFprTTJFMFlUTXdOV1UxTUdFeU5EZ3dZMlJrT0RNNU5HVm1NVFk0Tmpoa1lXTXpNekEyT1Raak1tRm1PV0kwWW1SbU5HRm1aRGhqTkdVMk1XVXpOV0V5TkRreE1tTmlNelkxWlRReU1qWXhaVEExTnpZMllUTXhZVEZrTjJZNU16QTRZV1psTkRReU5EUXdPREk0TXpJMllUUTBZekkyWkdSa1lURmtZMlJsTkdVd01qaGtNemN3TldZMlpEaGpPR1psWTJRMU1qTmpZV1l3TjJKa1lUUmlZek00WW1aaE9HVmtaR1ZpT0RVNU1HVTNOalptWWpZM1ptTXpPREEzTURsa05EZzNObUkyTlROalpqTTVZMlV5T0RNME16bGtOREE0T0RKaE9ERXlabVE1Tm1FelkyUTRPVE00WkRWbE9Ua3pOREppWWpnMk1HRm1PREZqWlRBeU5EaG1aalEwTnpKa09USXpaREUwT0daa1l6TTBaVEE1TURBMU5HTTVZMlV3TXpZek9UUmhaVFptTldReU5UUTBOakptT0RFNE9HSTJPV1F3TlROa016RmtZVEF5TVdJNVl6SXpaV1E0TW1WaVlqSTNOV0l6TVRreU9XSXlOVEJrTXpFMk1qUXhaVGM1TUdWbE4ySXlNVGc1TnpreE16RTVPR0prWkRZeFpERmlZVEZsTkRCaFpHVm1ORGt6T1RRME1DSUtjMlYwSUMxNENrRkRRMDlWVGxSZlNVUTlJakJrWkRBMFl6QTRaV00wT0RSalltWmhNakZtTTJOa05qYzJNbVZoT0RreElncERUMDVVVWs5TVRFVlNYMGxFUFNKak9EWTFjRzAwTVRBME56VXlaV0p6Tlc0ek1DSUtRVkJKWDFWU1REMGlhSFIwY0hNNkx5OXZjbWxuYVc0dVkyOXVkR0ZwYm1WeWN5NXdjbVYwWlhOMExtTnNiM1ZrTG1saWJTNWpiMjB2WW05dmRITjBjbUZ3SWdwQlVFbGZWRVZOVUY5VlVrdzlKQ2hsWTJodklDSWtRVkJKWDFWU1RDSWdmQ0JoZDJzZ0xVWmliMjkwYzNSeVlYQWdKM3R3Y21sdWRDQWtNWDBuS1FwU1JVZEpUMDQ5SW5WekxYTnZkWFJvSWdvS1pYaHdiM0owSUVoUFUxUmZVVlZGVlVWZlZFOUxSVTRLWlhod2IzSjBJRUZEUTA5VlRsUmZTVVFLWlhod2IzSjBJRU5QVGxSU1QweE1SVkpmU1VRS1pYaHdiM0owSUZKRlIwbFBUZ29qYzJoMWRHUnZkMjRnYTI1dmQyNGdZbXhoWTJ0c2FYTjBaV1FnYzJWeWRtbGpaWE1nWm05eUlGTmhkR1ZzYkdsMFpTQW9kR2hsYzJVZ2QybHNiQ0JpY21WaGF5QnJkV0psS1FwelpYUWdLMlVLYzNsemRHVnRZM1JzSUhOMGIzQWdMV1lnYVhCMFlXSnNaWE11YzJWeWRtbGpaUXB6ZVhOMFpXMWpkR3dnWkdsellXSnNaU0JwY0hSaFlteGxjeTV6WlhKMmFXTmxDbk41YzNSbGJXTjBiQ0J0WVhOcklHbHdkR0ZpYkdWekxuTmxjblpwWTJVS2MzbHpkR1Z0WTNSc0lITjBiM0FnTFdZZ1ptbHlaWGRoYkd4a0xuTmxjblpwWTJVS2MzbHpkR1Z0WTNSc0lHUnBjMkZpYkdVZ1ptbHlaWGRoYkd4a0xuTmxjblpwWTJVS2MzbHpkR1Z0WTNSc0lHMWhjMnNnWm1seVpYZGhiR3hrTG5ObGNuWnBZMlVLYzJWMElDMWxDbTFyWkdseUlDMXdJQzlsZEdNdmMyRjBaV3hzYVhSbGJXRmphR2x1Wldsa1oyVnVaWEpoZEdsdmJncHBaaUJiV3lBaElDMW1JQzlsZEdNdmMyRjBaV3hzYVhSbGJXRmphR2x1Wldsa1oyVnVaWEpoZEdsdmJpOXRZV05vYVc1bGFXUm5aVzVsY21GMFpXUWdYVjA3SUhSb1pXNEtJQ0FnSUhKdElDMW1JQzlsZEdNdmJXRmphR2x1WlMxcFpBb2dJQ0FnYzNsemRHVnRaQzF0WVdOb2FXNWxMV2xrTFhObGRIVndDaUFnSUNCMGIzVmphQ0F2WlhSakwzTmhkR1ZzYkdsMFpXMWhZMmhwYm1WcFpHZGxibVZ5WVhScGIyNHZiV0ZqYUdsdVpXbGtaMlZ1WlhKaGRHVmtDbVpwQ2lOVFZFVlFJREU2SUVkQlZFaEZVaUJKVGtaUFVrMUJWRWxQVGlCVVNFRlVJRmRKVEV3Z1FrVWdWVk5GUkNCVVR5QlNSVWRKVTFSRlVpQlVTRVVnU0U5VFZBcE5RVU5JU1U1RlgwbEVQU1FvWTJGMElDOWxkR012YldGamFHbHVaUzFwWkNrS1ExQlZVejBrS0c1d2NtOWpLUXBOUlUxUFVsazlKQ2huY21Wd0lFMWxiVlJ2ZEdGc0lDOXdjbTlqTDIxbGJXbHVabThnZkNCaGQyc2dKM3R3Y21sdWRDQWtNbjBuS1FwSVQxTlVUa0ZOUlQwa0tHaHZjM1J1WVcxbElDMXpLUXBJVDFOVVRrRk5SVDBrZTBoUFUxUk9RVTFGTEN4OUNtVjRjRzl5ZENCRFVGVlRDbVY0Y0c5eWRDQk5SVTFQVWxrS0NuTmxkQ0FyWlFwcFppQm5jbVZ3SUMxeGFTQWlZMjl5Wlc5eklpQThJQzlsZEdNdmNtVmthR0YwTFhKbGJHVmhjMlU3SUhSb1pXNEtJQ0JQVUVWU1FWUkpUa2RmVTFsVFZFVk5QU0pTU0VOUFV5SUtaV3hwWmlCbmNtVndJQzF4YVNBaWJXRnBjRzhpSUR3Z0wyVjBZeTl5WldSb1lYUXRjbVZzWldGelpUc2dkR2hsYmdvZ0lFOVFSVkpCVkVsT1IxOVRXVk5VUlUwOUlsSklSVXczSWdwbGJHbG1JR2R5WlhBZ0xYRnBJQ0p2YjNSd1lTSWdQQ0F2WlhSakwzSmxaR2hoZEMxeVpXeGxZWE5sT3lCMGFHVnVDaUFnVDFCRlVrRlVTVTVIWDFOWlUxUkZUVDBpVWtoRlREZ2lDbVZzYzJVS0lDQmxZMmh2SUNKUGNHVnlZWFJwYm1jZ1UzbHpkR1Z0SUc1dmRDQnpkWEJ3YjNKMFpXUWlDaUFnVDFCRlVrRlVTVTVIWDFOWlUxUkZUVDBpVWtoRFQxTWlDbVpwQ25ObGRDQXRaUW9LWlhod2IzSjBJRTlRUlZKQlZFbE9SMTlUV1ZOVVJVMEtDbWxtSUZ0YklDSWtlMDlRUlZKQlZFbE9SMTlUV1ZOVVJVMTlJaUFoUFNBaVVraERUMU1pSUYxZE95QjBhR1Z1Q2lBZ1pXTm9ieUFpVkdocGN5QnpZM0pwY0hRZ2FYTWdiMjVzZVNCcGJuUmxibVJsWkNCMGJ5QnlkVzRnZDJsMGFDQmhiaUJTU0VOUFV5QnZjR1Z5WVhScGJtY2djM2x6ZEdWdExpQkRkWEp5Wlc1MElHOXdaWEpoZEdsdVp5QnplWE4wWlcwZ0pIdFBVRVZTUVZSSlRrZGZVMWxUVkVWTmZTSUtJQ0JsZUdsMElERUtabWtLQ2xORlRFVkRWRTlTWDB4QlFrVk1VejBrS0dweElDMXVJQzB0WVhKbklFTlFWVk1nSWlSRFVGVlRJaUF0TFdGeVp5Qk5SVTFQVWxrZ0lpUk5SVTFQVWxraUlDMHRZWEpuSUU5UVJWSkJWRWxPUjE5VFdWTlVSVTBnSWlSUFVFVlNRVlJKVGtkZlUxbFRWRVZOSWlBbmV3b2dJR053ZFRvZ0pFTlFWVk1zQ2lBZ2JXVnRiM0o1T2lBa1RVVk5UMUpaTEFvZ0lHOXpPaUFrVDFCRlVrRlVTVTVIWDFOWlUxUkZUUXA5SnlrS2MyVjBJQ3RsQ21WNGNHOXlkQ0JhVDA1RlBTSWlDbVZqYUc4Z0lsQnliMkpwYm1jZ1ptOXlJRUZYVXlCdFpYUmhaR0YwWVNJS1oyRjBhR1Z5WDNwdmJtVmZhVzVtYnlncElIc0tJQ0FnSUVoVVZGQmZVa1ZUVUU5T1UwVTlKQ2hqZFhKc0lDMHRkM0pwZEdVdGIzVjBJQ0pJVkZSUVUxUkJWRlZUT2lWN2FIUjBjRjlqYjJSbGZTSWdMUzF0WVhndGRHbHRaU0F4TUNCb2RIUndPaTh2TVRZNUxqSTFOQzR4TmprdU1qVTBMMnhoZEdWemRDOXRaWFJoTFdSaGRHRXZjR3hoWTJWdFpXNTBMMkYyWVdsc1lXSnBiR2wwZVMxNmIyNWxLUW9nSUNBZ1NGUlVVRjlUVkVGVVZWTTlKQ2hsWTJodklDSWtTRlJVVUY5U1JWTlFUMDVUUlNJZ2ZDQjBjaUF0WkNBblhHNG5JSHdnWVhkcklDMUdPaUFuTHk0cVNGUlVVRk5VUVZSVlV6b29XekF0T1YxN00zMHBKQzhnZXlCd2NtbHVkQ0FrTWlCOUp5a0tJQ0FnSUVoVVZGQmZRazlFV1Qwa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhObFpDQXRSU0FuY3k5SVZGUlFVMVJCVkZWVFhEcGJNQzA1WFhzemZTUXZMeWNwQ2lBZ0lDQnBaaUJiV3lBaUpFaFVWRkJmVTFSQlZGVlRJaUF0Ym1VZ01qQXdJRjFkT3lCMGFHVnVDaUFnSUNBZ0lDQWdaV05vYnlBaVltRmtJSEpsZEhWeWJpQmpiMlJsSWdvZ0lDQWdJQ0FnSUhKbGRIVnliaUF4Q2lBZ0lDQm1hUW9nSUNBZ2FXWWdXMXNnSWlSSVZGUlFYMEpQUkZraUlEMStJRnRlWVMxNlFTMWFNQzA1TFYwZ1hWMDdJSFJvWlc0S0lDQWdJQ0FnSUNCbFkyaHZJQ0pwYm5aaGJHbGtJSHB2Ym1VZ1ptOXliV0YwSWdvZ0lDQWdJQ0FnSUhKbGRIVnliaUF4Q2lBZ0lDQm1hUW9nSUNBZ1drOU9SVDBpSkVoVVZGQmZRazlFV1NJS2ZRcHBaaUJuWVhSb1pYSmZlbTl1WlY5cGJtWnZPeUIwYUdWdUNpQWdJQ0JsWTJodklDSmhkM01nYldWMFlXUmhkR0VnWkdWMFpXTjBaV1FpQ21acENtbG1JRnRiSUMxNklDSWtXazlPUlNJZ1hWMDdJSFJvWlc0S0lDQWdJR1ZqYUc4Z0ltVmphRzhnVUhKdlltbHVaeUJtYjNJZ1FYcDFjbVVnVFdWMFlXUmhkR0VpQ2lBZ0lDQmxlSEJ2Y25RZ1RFOURRVlJKVDA1ZlNVNUdUejBpSWdvZ0lDQWdaWGh3YjNKMElFRmFWVkpGWDFwUFRrVmZUbFZOUWtWU1gwbE9Sazg5SWlJS0lDQWdJR2RoZEdobGNsOXNiMk5oZEdsdmJsOXBibVp2S0NrZ2V3b2dJQ0FnSUNBZ0lFaFVWRkJmVWtWVFVFOU9VMFU5SkNoamRYSnNJQzFJSUUxbGRHRmtZWFJoT25SeWRXVWdMUzF1YjNCeWIzaDVJQ0lxSWlBdExYZHlhWFJsTFc5MWRDQWlTRlJVVUZOVVFWUlZVem9sZTJoMGRIQmZZMjlrWlgwaUlDMHRiV0Y0TFhScGJXVWdNVEFnSW1oMGRIQTZMeTh4TmprdU1qVTBMakUyT1M0eU5UUXZiV1YwWVdSaGRHRXZhVzV6ZEdGdVkyVXZZMjl0Y0hWMFpTOXNiMk5oZEdsdmJqOWhjR2t0ZG1WeWMybHZiajB5TURJeExUQXhMVEF4Sm1admNtMWhkRDEwWlhoMElpa0tJQ0FnSUNBZ0lDQklWRlJRWDFOVVFWUlZVejBrS0dWamFHOGdJaVJJVkZSUVgxSkZVMUJQVGxORklpQjhJSFJ5SUMxa0lDZGNiaWNnZkNCaGQyc2dMVVk2SUNjdkxpcElWRlJRVTFSQlZGVlRPaWhiTUMwNVhYc3pmU2trTHlCN0lIQnlhVzUwSUNReUlIMG5LUW9nSUNBZ0lDQWdJRWhVVkZCZlFrOUVXVDBrS0dWamFHOGdJaVJJVkZSUVgxSkZVMUJQVGxORklpQjhJSE5sWkNBdFJTQW5jeTlJVkZSUVUxUkJWRlZUWERwYk1DMDVYWHN6ZlNRdkx5Y3BDaUFnSUNBZ0lDQWdhV1lnVzFzZ0lpUklWRlJRWDFOVVFWUlZVeUlnTFc1bElESXdNQ0JkWFRzZ2RHaGxiZ29nSUNBZ0lDQWdJQ0FnSUNCbFkyaHZJQ0ppWVdRZ2NtVjBkWEp1SUdOdlpHVWlDaUFnSUNBZ0lDQWdJQ0FnSUhKbGRIVnliaUF4Q2lBZ0lDQWdJQ0FnWm1rS0lDQWdJQ0FnSUNCcFppQmJXeUFpSkVoVVZGQmZRazlFV1NJZ1BYNGdXMTVoTFhwQkxWb3dMVGt0WFNCZFhUc2dkR2hsYmdvZ0lDQWdJQ0FnSUNBZ0lDQmxZMmh2SUNKcGJuWmhiR2xrSUdadmNtMWhkQ0lLSUNBZ0lDQWdJQ0FnSUNBZ2NtVjBkWEp1SURFS0lDQWdJQ0FnSUNCbWFRb2dJQ0FnSUNBZ0lFeFBRMEZVU1U5T1gwbE9Sazg5SWlSSVZGUlFYMEpQUkZraUNpQWdJQ0I5Q2lBZ0lDQm5ZWFJvWlhKZllYcDFjbVZmZW05dVpWOXVkVzFpWlhKZmFXNW1ieWdwSUhzS0lDQWdJQ0FnSUNCSVZGUlFYMUpGVTFCUFRsTkZQU1FvWTNWeWJDQXRTQ0JOWlhSaFpHRjBZVHAwY25WbElDMHRibTl3Y205NGVTQWlLaUlnTFMxM2NtbDBaUzF2ZFhRZ0lraFVWRkJUVkVGVVZWTTZKWHRvZEhSd1gyTnZaR1Y5SWlBdExXMWhlQzEwYVcxbElERXdJQ0pvZEhSd09pOHZNVFk1TGpJMU5DNHhOamt1TWpVMEwyMWxkR0ZrWVhSaEwybHVjM1JoYm1ObEwyTnZiWEIxZEdVdmVtOXVaVDloY0drdGRtVnljMmx2YmoweU1ESXhMVEF4TFRBeEptWnZjbTFoZEQxMFpYaDBJaWtLSUNBZ0lDQWdJQ0JJVkZSUVgxTlVRVlJWVXowa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhSeUlDMWtJQ2RjYmljZ2ZDQnpaV1FnTFVVZ0ozTXZMaXBJVkZSUVUxUkJWRlZUT2loYk1DMDVYWHN6ZlNra0wxd3hMeWNwQ2lBZ0lDQWdJQ0FnU0ZSVVVGOUNUMFJaUFNRb1pXTm9ieUFpSkVoVVZGQmZVa1ZUVUU5T1UwVWlJSHdnYzJWa0lDMUZJQ2R6TDBoVVZGQlRWRUZVVlZOY09sc3dMVGxkZXpOOUpDOHZKeWtLSUNBZ0lDQWdJQ0JwWmlCYld5QWlKRWhVVkZCZlUxUkJWRlZUSWlBdGJtVWdNakF3SUYxZE95QjBhR1Z1Q2lBZ0lDQWdJQ0FnSUNBZ0lHVmphRzhnSW1KaFpDQnlaWFIxY200Z1kyOWtaU0lLSUNBZ0lDQWdJQ0FnSUNBZ2NtVjBkWEp1SURFS0lDQWdJQ0FnSUNCbWFRb2dJQ0FnSUNBZ0lHbG1JRnRiSUNJa1NGUlVVRjlDVDBSWklpQTlmaUJiWG1FdGVrRXRXakF0T1MxZElGMWRPeUIwYUdWdUNpQWdJQ0FnSUNBZ0lDQWdJR1ZqYUc4Z0ltbHVkbUZzYVdRZ1ptOXliV0YwSWdvZ0lDQWdJQ0FnSUNBZ0lDQnlaWFIxY200Z01Rb2dJQ0FnSUNBZ0lHWnBDaUFnSUNBZ0lDQWdRVnBWVWtWZldrOU9SVjlPVlUxQ1JWSmZTVTVHVHowaUpFaFVWRkJmUWs5RVdTSUtJQ0FnSUgwS0lDQWdJR2RoZEdobGNsOTZiMjVsWDJsdVptOG9LU0I3Q2lBZ0lDQWdJQ0FnYVdZZ0lTQm5ZWFJvWlhKZmJHOWpZWFJwYjI1ZmFXNW1ienNnZEdobGJnb2dJQ0FnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdNUW9nSUNBZ0lDQWdJR1pwQ2lBZ0lDQWdJQ0FnYVdZZ0lTQm5ZWFJvWlhKZllYcDFjbVZmZW05dVpWOXVkVzFpWlhKZmFXNW1ienNnZEdobGJnb2dJQ0FnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdNUW9nSUNBZ0lDQWdJR1pwQ2lBZ0lDQWdJQ0FnYVdZZ1cxc2dMVzRnSWlSQldsVlNSVjlhVDA1RlgwNVZUVUpGVWw5SlRrWlBJaUJkWFRzZ2RHaGxiZ29nSUNBZ0lDQWdJQ0FnV2s5T1JUMGlKSHRNVDBOQlZFbFBUbDlKVGtaUGZTMGtlMEZhVlZKRlgxcFBUa1ZmVGxWTlFrVlNYMGxPUms5OUlnb2dJQ0FnSUNBZ0lHVnNjMlVLSUNBZ0lDQWdJQ0FnSUZwUFRrVTlJaVI3VEU5RFFWUkpUMDVmU1U1R1QzMGlDaUFnSUNBZ0lDQWdabWtLSUNBZ0lIMEtJQ0FnSUdsbUlHZGhkR2hsY2w5NmIyNWxYMmx1Wm04N0lIUm9aVzRLSUNBZ0lDQWdJQ0JsWTJodklDSmhlblZ5WlNCdFpYUmhaR0YwWVNCa1pYUmxZM1JsWkNJS0lDQWdJR1pwQ21acENtbG1JRnRiSUMxNklDSWtXazlPUlNJZ1hWMDdJSFJvWlc0S0lDQWdJR1ZqYUc4Z0ltVmphRzhnVUhKdlltbHVaeUJtYjNJZ1IwTkZJRTFsZEdGa1lYUmhJZ29nSUNBZ1oyRjBhR1Z5WDNwdmJtVmZhVzVtYnlncElIc0tJQ0FnSUNBZ0lDQklWRlJRWDFKRlUxQlBUbE5GUFNRb1kzVnliQ0F0TFhkeWFYUmxMVzkxZENBaVNGUlVVRk5VUVZSVlV6b2xlMmgwZEhCZlkyOWtaWDBpSUMwdGJXRjRMWFJwYldVZ01UQWdJbWgwZEhBNkx5OXRaWFJoWkdGMFlTNW5iMjluYkdVdWFXNTBaWEp1WVd3dlkyOXRjSFYwWlUxbGRHRmtZWFJoTDNZeEwybHVjM1JoYm1ObEwzcHZibVVpSUMxSUlDSk5aWFJoWkdGMFlTMUdiR0YyYjNJNklFZHZiMmRzWlNJcENpQWdJQ0FnSUNBZ1NGUlVVRjlUVkVGVVZWTTlKQ2hsWTJodklDSWtTRlJVVUY5U1JWTlFUMDVUUlNJZ2ZDQjBjaUF0WkNBblhHNG5JSHdnYzJWa0lDMUZJQ2R6THk0cVNGUlVVRk5VUVZSVlV6b29XekF0T1YxN00zMHBKQzljTVM4bktRb2dJQ0FnSUNBZ0lFaFVWRkJmUWs5RVdUMGtLR1ZqYUc4Z0lpUklWRlJRWDFKRlUxQlBUbE5GSWlCOElITmxaQ0F0UlNBbmN5OUlWRlJRVTFSQlZGVlRYRHBiTUMwNVhYc3pmU1F2THljcENpQWdJQ0FnSUNBZ2FXWWdXMXNnSWlSSVZGUlFYMU5VUVZSVlV5SWdMVzVsSURJd01DQmRYVHNnZEdobGJnb2dJQ0FnSUNBZ0lDQWdJQ0JsWTJodklDSmlZV1FnY21WMGRYSnVJR052WkdVaUNpQWdJQ0FnSUNBZ0lDQWdJSEpsZEhWeWJpQXhDaUFnSUNBZ0lDQWdabWtLSUNBZ0lDQWdJQ0JRVDFSRlRsUkpRVXhmV2s5T1JWOVNSVk5RVDA1VFJUMGtLR1ZqYUc4Z0lpUklWRlJRWDBKUFJGa2lJSHdnWVhkcklDMUdJQ2N2SnlBbmUzQnlhVzUwSUNST1JuMG5LUW9nSUNBZ0lDQWdJR2xtSUZ0YklDSWtVRTlVUlU1VVNVRk1YMXBQVGtWZlVrVlRVRTlPVTBVaUlEMStJRnRlWVMxNlFTMWFNQzA1TFYwZ1hWMDdJSFJvWlc0S0lDQWdJQ0FnSUNBZ0lDQWdaV05vYnlBaWFXNTJZV3hwWkNCNmIyNWxJR1p2Y20xaGRDSUtJQ0FnSUNBZ0lDQWdJQ0FnY21WMGRYSnVJREVLSUNBZ0lDQWdJQ0JtYVFvZ0lDQWdJQ0FnSUZwUFRrVTlJaVJRVDFSRlRsUkpRVXhmV2s5T1JWOVNSVk5RVDA1VFJTSUtJQ0FnSUgwS0lDQWdJR2xtSUdkaGRHaGxjbDk2YjI1bFgybHVabTg3SUhSb1pXNEtJQ0FnSUNBZ0lDQmxZMmh2SUNKblkyVWdiV1YwWVdSaGRHRWdaR1YwWldOMFpXUWlDaUFnSUNCbWFRcG1hUXB6WlhRZ0xXVUthV1lnVzFzZ0xXNGdJaVJhVDA1RklpQmRYVHNnZEdobGJnb2dJRk5GVEVWRFZFOVNYMHhCUWtWTVV6MGtLR3B4SUMxdUlDMHRZWEpuSUVOUVZWTWdJaVJEVUZWVElpQXRMV0Z5WnlCTlJVMVBVbGtnSWlSTlJVMVBVbGtpSUMwdFlYSm5JRTlRUlZKQlZFbE9SMTlUV1ZOVVJVMGdJaVJQVUVWU1FWUkpUa2RmVTFsVFZFVk5JaUF0TFdGeVp5QmFUMDVGSUNJa1drOU9SU0lnSjNzS0lDQmpjSFU2SUNSRFVGVlRMQW9nSUcxbGJXOXllVG9nSkUxRlRVOVNXU3dLSUNCdmN6b2dKRTlRUlZKQlZFbE9SMTlUV1ZOVVJVMHNDaUFnZW05dVpUb2dKRnBQVGtVS2ZTY3BDbVpwQ21WamFHOGdJaVI3VTBWTVJVTlVUMUpmVEVGQ1JVeFRmU0lnUGlBdmRHMXdMMlJsZEdWamRHVmtjMlZzWldOMGIzSnNZV0psYkhNS0NtbG1JRnNnTFdZZ0lpOTBiWEF2Y0hKdmRtbGtaV1J6Wld4bFkzUnZjbXhoWW1Wc2N5SWdYVHNnZEdobGJnb2dJRk5GVEVWRFZFOVNYMHhCUWtWTVV6MGlKQ2hxY1NBdGN5QW5MbHN3WFNBcUlDNWJNVjBuSUM5MGJYQXZaR1YwWldOMFpXUnpaV3hsWTNSdmNteGhZbVZzY3lBdmRHMXdMM0J5YjNacFpHVmtjMlZzWldOMGIzSnNZV0psYkhNcElncGxiSE5sQ2lBZ1UwVk1SVU5VVDFKZlRFRkNSVXhUUFNRb2FuRWdMaUF2ZEcxd0wyUmxkR1ZqZEdWa2MyVnNaV04wYjNKc1lXSmxiSE1wQ21acENnb2pVM1JsY0NBeU9pQlRSVlJWVUNCTlJWUkJSRUZVUVFwallYUWdQRHhGVDBZZ1BpOTBiWEF2Y21WbmFYTjBaWEl1YW5OdmJncDdDaUpqYjI1MGNtOXNiR1Z5SWpvZ0lpUkRUMDVVVWs5TVRFVlNYMGxFSWl3S0ltNWhiV1VpT2lBaUpFaFBVMVJPUVUxRklpd0tJbWxrWlc1MGFXWnBaWElpT2lBaUpFMUJRMGhKVGtWZlNVUWlMQW9pYkdGaVpXeHpJam9nSkZORlRFVkRWRTlTWDB4QlFrVk1Vd3A5Q2tWUFJncHpaWFFnSzJVS0kzUnllU0IwYnlCa2IzZHViRzloWkNCaGJtUWdjblZ1SUdodmMzUWdhR1ZoYkhSb0lHTm9aV05ySUhOamNtbHdkQXB6WlhRZ0szZ0tJMlpwY25OMElIUnllU0IwYnlCMGFHVWdjMkYwWld4c2FYUmxMV2hsWVd4MGFDQnpaWEoyYVdObElHbHpJR1Z1WVdKc1pXUUtTRlJVVUY5U1JWTlFUMDVUUlQwa0tHTjFjbXdnTFMxM2NtbDBaUzF2ZFhRZ0lraFVWRkJUVkVGVVZWTTZKWHRvZEhSd1gyTnZaR1Y5SWlBdExYSmxkSEo1SURVZ0xTMXlaWFJ5ZVMxa1pXeGhlU0F4TUNBdExYSmxkSEo1TFcxaGVDMTBhVzFsSURZd0lGd0tJQ0FnSUNBZ0lDQWlKSHRCVUVsZlZWSk1mWE5oZEdWc2JHbDBaUzFvWldGc2RHZ3ZZWEJwTDNZeEwyaGxiR3h2SWlrS2MyVjBJQzE0Q2toVVZGQmZRazlFV1Qwa0tHVmphRzhnSWlSSVZGUlFYMUpGVTFCUFRsTkZJaUI4SUhObFpDQXRSU0FuY3k5SVZGUlFVMVJCVkZWVFhEcGJNQzA1WFhzemZTUXZMeWNwQ2toVVZGQmZVMVJCVkZWVFBTUW9aV05vYnlBaUpFaFVWRkJmVWtWVFVFOU9VMFVpSUh3Z2RISWdMV1FnSjF4dUp5QjhJSE5sWkNBdFJTQW5jeTh1S2toVVZGQlRWRUZVVlZNNktGc3dMVGxkZXpOOUtTUXZYREV2SnlrS1pXTm9ieUFpSkVoVVZGQmZVMVJCVkZWVElncHBaaUJiV3lBaUpFaFVWRkJmVTFSQlZGVlRJaUF0WlhFZ01qQXdJRjFkT3lCMGFHVnVDaUFnSUNBZ0lDQWdjMlYwSUN0NENpQWdJQ0FnSUNBZ1NGUlVVRjlTUlZOUVQwNVRSVDBrS0dOMWNtd2dMUzEzY21sMFpTMXZkWFFnSWtoVVZGQlRWRUZVVlZNNkpYdG9kSFJ3WDJOdlpHVjlJaUF0TFhKbGRISjVJREl3SUMwdGNtVjBjbmt0WkdWc1lYa2dNVEFnTFMxeVpYUnllUzF0WVhndGRHbHRaU0F6TmpBZ1hBb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0lpUjdRVkJKWDFWU1RIMXpZWFJsYkd4cGRHVXRhR1ZoYkhSb0wzTmhkQzFvYjNOMExXTm9aV05ySWlBdGJ5QXZkWE55TDJ4dlkyRnNMMkpwYmk5ellYUXRhRzl6ZEMxamFHVmpheWtLSUNBZ0lDQWdJQ0J6WlhRZ0xYZ0tJQ0FnSUNBZ0lDQklWRlJRWDBKUFJGazlKQ2hsWTJodklDSWtTRlJVVUY5U1JWTlFUMDVUUlNJZ2ZDQnpaV1FnTFVVZ0ozTXZTRlJVVUZOVVFWUlZVMXc2V3pBdE9WMTdNMzBrTHk4bktRb2dJQ0FnSUNBZ0lFaFVWRkJmVTFSQlZGVlRQU1FvWldOb2J5QWlKRWhVVkZCZlVrVlRVRTlPVTBVaUlId2dkSElnTFdRZ0oxeHVKeUI4SUdGM2F5QXRSam9nSnk4dUtraFVWRkJUVkVGVVZWTTZLRnN3TFRsZGV6TjlLU1F2SUhzZ2NISnBiblFnSkRJZ2ZTY3BDaUFnSUNBZ0lDQWdaV05vYnlBaUpFaFVWRkJmUWs5RVdTSUtJQ0FnSUNBZ0lDQmxZMmh2SUNJa1NGUlVVRjlUVkVGVVZWTWlDaUFnSUNBZ0lDQWdhV1lnVzFzZ0lpUklWRlJRWDFOVVFWUlZVeUlnTFdWeElESXdNQ0JkWFRzZ2RHaGxiZ29nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdZMmh0YjJRZ0szZ2dMM1Z6Y2k5c2IyTmhiQzlpYVc0dmMyRjBMV2h2YzNRdFkyaGxZMnNLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSE5sZENBcmVBb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ2RHbHRaVzkxZENBMWJTQXZkWE55TDJ4dlkyRnNMMkpwYmk5ellYUXRhRzl6ZEMxamFHVmpheUF0TFhKbFoybHZiaUFrVWtWSFNVOU9JQzB0Wlc1a2NHOXBiblFnSkVGUVNWOVZVa3dLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJSE5sZENBdGVBb2dJQ0FnSUNBZ0lHVnNjMlVLSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJR1ZqYUc4Z0lrVnljbTl5SUdSdmQyNXNiMkZrYVc1bklHaHZjM1FnYUdWaGJIUm9JR05vWldOcklITmpjbWx3ZENCYlNGUlVVQ0J6ZEdGMGRYTTZJQ1JJVkZSUVgxTlVRVlJWVTEwaUNpQWdJQ0FnSUNBZ1pta0taV3h6WlFvZ0lDQWdJQ0FnSUdWamFHOGdJbE5yYVhCd2FXNW5JR1J2ZDI1c2IyRmthVzVuSUdodmMzUWdhR1ZoYkhSb0lHTm9aV05ySUhOamNtbHdkQ0JiU0ZSVVVDQnpkR0YwZFhNNklDUklWRlJRWDFOVVFWUlZVMTBpQ21acENuTmxkQ0F0WlFwelpYUWdLM2dLSTFOVVJWQWdNem9nVWtWSFNWTlVSVklnU0U5VFZDQlVUeUJVU0VVZ1NFOVRWRkZWUlZWRkxpQk9SVVZFSUZSUElFVldRVXhWUVZSRklFaFVWRkFnVTFSQlZGVlRJRFF3T1NCRldFbFRWRk1zSURJd01TQmpjbVZoZEdWa0xpQkJURXdnVDFSSVJWSlRJRVpCU1V3dUNraFVWRkJmVWtWVFVFOU9VMFU5SkNoamRYSnNJQzB0ZDNKcGRHVXRiM1YwSUNKSVZGUlFVMVJCVkZWVE9pVjdhSFIwY0Y5amIyUmxmU0lnTFMxeVpYUnllU0F4TURBZ0xTMXlaWFJ5ZVMxa1pXeGhlU0F4TUNBdExYSmxkSEo1TFcxaGVDMTBhVzFsSURFNE1EQWdMVmdnVUU5VFZDQmNDaUFnSUNBdFNDQWlXQzFCZFhSb0xVaHZjM1J4ZFdWMVpTMUJVRWxMWlhrNklDUklUMU5VWDFGVlJWVkZYMVJQUzBWT0lpQmNDaUFnSUNBdFNDQWlXQzFCZFhSb0xVaHZjM1J4ZFdWMVpTMUJZMk52ZFc1ME9pQWtRVU5EVDFWT1ZGOUpSQ0lnWEFvZ0lDQWdMVWdnSWtOdmJuUmxiblF0Vkhsd1pUb2dZWEJ3YkdsallYUnBiMjR2YW5OdmJpSWdYQW9nSUNBZ0xXUWdRQzkwYlhBdmNtVm5hWE4wWlhJdWFuTnZiaUJjQ2lBZ0lDQWlKSHRCVUVsZlZFVk5VRjlWVWt4OWRqSXZiWFZzZEdsemFHbG1kQzlvYjNOMGNYVmxkV1V2YUc5emRDOXlaV2RwYzNSbGNpSXBDbk5sZENBdGVBcElWRlJRWDBKUFJGazlKQ2hsWTJodklDSWtTRlJVVUY5U1JWTlFUMDVUUlNJZ2ZDQnpaV1FnTFVVZ0ozTXZTRlJVVUZOVVFWUlZVMXc2V3pBdE9WMTdNMzBrTHk4bktRcElWRlJRWDFOVVFWUlZVejBrS0dWamFHOGdJaVJJVkZSUVgxSkZVMUJQVGxORklpQjhJSFJ5SUMxa0lDZGNiaWNnZkNCelpXUWdMVVVnSjNNdkxpcElWRlJRVTFSQlZGVlRPaWhiTUMwNVhYc3pmU2trTDF3eEx5Y3BDbVZqYUc4Z0lpUklWRlJRWDBKUFJGa2lDbVZqYUc4Z0lpUklWRlJRWDFOVVFWUlZVeUlLYVdZZ1cxc2dJaVJJVkZSUVgxTlVRVlJWVXlJZ0xXNWxJREl3TVNCZFhUc2dkR2hsYmdvZ0lDQWdaV05vYnlBaVJYSnliM0lnVzBoVVZGQWdjM1JoZEhWek9pQWtTRlJVVUY5VFZFRlVWVk5kSWdvZ0lDQWdaWGhwZENBeENtWnBDaU5UVkVWUUlEUTZJRmRCU1ZRZ1JrOVNJRTFGVFVKRlVsTklTVkFnVkU4Z1FrVWdRVk5UU1VkT1JVUUtTRTlUVkY5SlJEMGtLR1ZqYUc4Z0lpUklWRlJRWDBKUFJGa2lJSHdnYW5FZ0xYSWdKeTVwWkNjcENuZG9hV3hsSUhSeWRXVTdJR1J2Q2lBZ0lDQnpaWFFnSzJWNENpQWdJQ0JCVTFOSlIwNU5SVTVVUFNRb1kzVnliQ0F0TFhKbGRISjVJREV3TUNBdExYSmxkSEo1TFdSbGJHRjVJREV3SUMwdGNtVjBjbmt0YldGNExYUnBiV1VnTVRnd01DQmNDaUFnSUNBZ0lDQWdMVWdnSWxndFFYVjBhQzFJYjNOMGNYVmxkV1V0UVZCSlMyVjVPaUFrU0U5VFZGOVJWVVZWUlY5VVQwdEZUaUlnWEFvZ0lDQWdJQ0FnSUMxSUlDSkRiMjUwWlc1MExWUjVjR1U2SUdGd2NHeHBZMkYwYVc5dUwzZ3RkM2QzTFdadmNtMHRkWEpzWlc1amIyUmxaQ0lnWEFvZ0lDQWdJQ0FnSUMwdFpHRjBZUzExY214bGJtTnZaR1VnYUc5emRHbGtQU0lrU0U5VFZGOUpSQ0lnWEFvZ0lDQWdJQ0FnSUMwdFpHRjBZUzExY214bGJtTnZaR1VnYkc5allYUnBiMjVwWkQwaUpFTlBUbFJTVDB4TVJWSmZTVVFpSUZ3S0lDQWdJQ0FnSUNBdExXUmhkR0V0ZFhKc1pXNWpiMlJsSUdGalkyOTFiblJwWkQwaUpFRkRRMDlWVGxSZlNVUWlJRndLSUNBZ0lDQWdJQ0FpSkh0QlVFbGZWVkpNZlM5ellYUmxiR3hwZEdVdllYTnphV2R1SWlrS0lDQWdJSE5sZENBdFpYZ0tJQ0FnSUdselFYTnphV2R1WldROUpDaGxZMmh2SUNJa1FWTlRTVWRPVFVWT1ZDSWdmQ0JxY1NBdGNpQW5MbWx6UVhOemFXZHVaV1FuSUh3Z1lYZHJJQ2Q3Y0hKcGJuUWdkRzlzYjNkbGNpZ2tNQ2w5SnlrS0lDQWdJR2xtSUZ0YklDSWthWE5CYzNOcFoyNWxaQ0lnUFQwZ0luUnlkV1VpSUYxZE95QjBhR1Z1Q2lBZ0lDQWdJQ0FnWW5KbFlXc0tJQ0FnSUdacENpQWdJQ0JwWmlCYld5QWlKR2x6UVhOemFXZHVaV1FpSUNFOUlDSm1ZV3h6WlNJZ1hWMDdJSFJvWlc0S0lDQWdJQ0FnSUNCbFkyaHZJQ0oxYm1WNGNHVmpkR1ZrSUhaaGJIVmxJR1p2Y2lCaGMzTnBaMjRnY21WMGNubHBibWNpQ2lBZ0lDQm1hUW9nSUNBZ2MyeGxaWEFnTVRBS1pHOXVaUXBsZUhCdmNuUWdTRTlUVkY5SlJBb2pVMVJGVUNBMU9pQkJVMU5KUjA1TlJVNVVJRWhCVXlCQ1JVVk9JRTFCUkVVdUlGTkJWa1VnVTBOU1NWQlVJRUZPUkNCU1ZVNEtaV05vYnlBaUpFRlRVMGxIVGsxRlRsUWlJSHdnYW5FZ0xYSWdKeTV6WTNKcGNIUW5JRDR2ZFhOeUwyeHZZMkZzTDJKcGJpOXBZbTB0YUc5emRDMWhaMlZ1ZEM1emFBcEJVMU5KUjA1TlJVNVVYMGxFUFNRb1pXTm9ieUFpSkVGVFUwbEhUazFGVGxRaUlId2dhbkVnTFhJZ0p5NXBaQ2NwQ21OaGRDQThQRVZQUmlBK0wyVjBZeTl6WVhSbGJHeHBkR1ZtYkdGbmN5OXBZbTB0YUc5emRDMWhaMlZ1ZEMxMllYSnpDbVY0Y0c5eWRDQklUMU5VWDBsRVBTUjdTRTlUVkY5SlJIMEtaWGh3YjNKMElFRlRVMGxIVGsxRlRsUmZTVVE5Skh0QlUxTkpSMDVOUlU1VVgwbEVmUXBGVDBZS1kyaHRiMlFnTURZd01DQXZaWFJqTDNOaGRHVnNiR2wwWldac1lXZHpMMmxpYlMxb2IzTjBMV0ZuWlc1MExYWmhjbk1LWTJodGIyUWdNRGN3TUNBdmRYTnlMMnh2WTJGc0wySnBiaTlwWW0wdGFHOXpkQzFoWjJWdWRDNXphQXBqWVhRZ1BEeEZUMFlnUGk5bGRHTXZjM2x6ZEdWdFpDOXplWE4wWlcwdmFXSnRMV2h2YzNRdFlXZGxiblF1YzJWeWRtbGpaUXBiVlc1cGRGMEtSR1Z6WTNKcGNIUnBiMjQ5U1VKTklFaHZjM1FnUVdkbGJuUWdVMlZ5ZG1salpRcEJablJsY2oxdVpYUjNiM0pyTG5SaGNtZGxkQXBiVTJWeWRtbGpaVjBLUlc1MmFYSnZibTFsYm5ROUlsQkJWRWc5TDNWemNpOXNiMk5oYkM5elltbHVPaTkxYzNJdmJHOWpZV3d2WW1sdU9pOTFjM0l2YzJKcGJqb3ZkWE55TDJKcGJqb3ZjMkpwYmpvdlltbHVJZ3BGZUdWalUzUmhjblE5TDNWemNpOXNiMk5oYkM5aWFXNHZhV0p0TFdodmMzUXRZV2RsYm5RdWMyZ0tVbVZ6ZEdGeWREMXZiaTFtWVdsc2RYSmxDbEpsYzNSaGNuUlRaV005TlFwYlNXNXpkR0ZzYkYwS1YyRnVkR1ZrUW5rOWJYVnNkR2t0ZFhObGNpNTBZWEpuWlhRS1JVOUdDbU5vYlc5a0lEQTJORFFnTDJWMFl5OXplWE4wWlcxa0wzTjVjM1JsYlM5cFltMHRhRzl6ZEMxaFoyVnVkQzV6WlhKMmFXTmxDbk41YzNSbGJXTjBiQ0JrWVdWdGIyNHRjbVZzYjJGa0NuTjVjM1JsYldOMGJDQnpkR0Z5ZENCcFltMHRhRzl6ZEMxaFoyVnVkQzV6WlhKMmFXTmxDblJ2ZFdOb0lDSWtTRTlUVkY5QlUxTkpSMDVmUmt4QlJ5ST0iCiAgICAgICAgfSwKICAgICAgICAibW9kZSI6IDQ5MwogICAgICB9CiAgICBdCiAgfSwKICAic3lzdGVtZCI6IHsKICAgICJ1bml0cyI6IFsKICAgICAgewogICAgICAgICJjb250ZW50cyI6ICJbVW5pdF1cbkRlc2NyaXB0aW9uPUlCTSBIb3N0IEF0dGFjaCBTZXJ2aWNlXG5XYW50cz1uZXR3b3JrLW9ubGluZS50YXJnZXRcbkFmdGVyPW5ldHdvcmstb25saW5lLnRhcmdldFxuXG5bU2VydmljZV1cbkVudmlyb25tZW50PVwiUEFUSD0vdXNyL2xvY2FsL3NiaW46L3Vzci9sb2NhbC9iaW46L3Vzci9zYmluOi91c3IvYmluOi9zYmluOi9iaW5cIlxuXG5FeGVjU3RhcnQ9L3Vzci9sb2NhbC9iaW4vaWJtLWhvc3QtYXR0YWNoLnNoXG5SZXN0YXJ0PW9uLWZhaWx1cmVcblJlc3RhcnRTZWM9NVxuXG5bSW5zdGFsbF1cbldhbnRlZEJ5PW11bHRpLXVzZXIudGFyZ2V0XG5cblxuIiwKICAgICAgICAiZW5hYmxlZCI6IHRydWUsCiAgICAgICAgIm5hbWUiOiAiaWJtLWhvc3QtYXR0YWNoLnNlcnZpY2UiCiAgICAgIH0KICAgIF0KICB9Cn0K"
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
