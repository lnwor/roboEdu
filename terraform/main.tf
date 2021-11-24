variable "corso" {
  type = string
  description = "nome del corso di studi"
}

variable "anno" {
  type = string
  description = "anno del corso di studi"
}

variable "id" {
  type = string
  description = "id univoco della lezione"
}

variable "counter" {
  type = string
  description = "contatore relativo alla lezione"
}

locals {
	varNames = join("-", [var.corso, var.anno, var.id, var.counter])
	keyName = join("-", [local.varNames, "key"])
	pathKey = join("", ["../secrets/ssh/", local.keyName])
	vpsName = join("-", [local.varNames, "client"])
}

terraform {
	required_providers {
		hcloud = {
			source = "hetznercloud/hcloud"
			version = "1.20.1"
		}
	}
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
	token = chomp(file("../secrets/hcloud_key"))
}

#  Main ssh key
resource "hcloud_ssh_key"  "myKey" {
  name       = local.keyName
  public_key = file(join("", [local.pathKey, ".pub"]))
}

resource "hcloud_server" "myVps" {
  name        = local.vpsName
  image       = "ubuntu-20.04"
  server_type = "cpx11"
  ssh_keys    = ["${hcloud_ssh_key.myKey.name}"]
}

output "teams_client_public_ipv4" {
  value = "${hcloud_server.myVps.ipv4_address}"
}
