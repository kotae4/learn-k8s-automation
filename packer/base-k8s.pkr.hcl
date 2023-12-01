packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "~> 1"
    }
  }
}

variable "vm_cpus" {
  type    = string
  default = "2"
}

variable "vm_disk_size" {
  type    = string
  default = "21440"
}

variable "iso_checksum" {
  type    = string
  default = "file:https://releases.ubuntu.com/22.04.3/SHA256SUMS"
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/22.04.3/ubuntu-22.04.3-live-server-amd64.iso"
}

variable "vm_memory" {
  type    = string
  default = "2048"
}

variable "vm_name" {
  type    = string
  default = "ubuntu-jammy"
}

variable "default_username" {
  type = string
  default = "vagrant"
}

variable "default_password" {
  type = string
  default = "toor1!"
}

source "hyperv-iso" "ubuntujammy" {
  boot_wait            = "5s"
  # NOTE ubuntu >= 20.x now uses cloud-init instead of preseed.
  boot_command         = [
    "e<down><down><down><end>",
    " autoinstall ds=nocloud;",
    "<F10>",
  ]
  # NOTE using cd_files requires oscdimg to be on PATH
  # get it here: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
  cd_files = [
    "http/*"
  ]
  cd_label = "cidata"
  communicator         = "ssh"
  vm_name              = "${var.vm_name}"
  cpus                 = "${var.vm_cpus}"
  memory               = "${var.vm_memory}"
  disk_size            = "${var.vm_disk_size}"
  enable_secure_boot   = false
  generation           = 2
  guest_additions_mode = "disable"
  iso_checksum         = "${var.iso_checksum}"
  iso_url              = "${var.iso_url}"
  shutdown_command     = "echo '${var.default_password}' | sudo -S -E shutdown -P now"
  ssh_username         = "${var.default_username}"
  ssh_password         = "${var.default_password}"
  ssh_timeout          = "30m"
}

build {
  name = "ubuntu-jammy"
  
  sources = [
    "source.hyperv-iso.ubuntujammy",
  ]

}