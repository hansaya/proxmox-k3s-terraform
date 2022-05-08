terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = ">=2.8.0"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://${var.proxmox-host}:8006/api2/json"
  pm_user         = var.proxmox-user
  pm_password     = var.proxmox-password
  pm_tls_insecure = "true"
  pm_parallel     = 10
}

resource "proxmox_vm_qemu" "proxmox_vm_master" {
  count       = var.num_k3s_masters
  name        = "k3s-master-${count.index}"
  target_node = var.proxmox_cluster_name
  clone       = var.tamplate_vm_name
  os_type     = "cloud-init"
  agent       = 1
  memory      = var.num_k3s_masters_mem
  cores       = var.number_of_cores
  onboot      = var.start_on_boot
  disk {
    slot            = 0
    size            = var.num_k3s_nodes_master_storage
    type            = "scsi"
    storage         = "local-lvm"
  }

  ipconfig0 = "ip=${cidrhost("${var.ip_sub}/${var.ip_sub_mask}", var.master_ip_start+count.index)}/${var.ip_sub_mask},gw=${var.default_gateway}"

}

resource "proxmox_vm_qemu" "proxmox_vm_workers" {
  count       = var.num_k3s_nodes
  name        = "k3s-worker-${count.index}"
  target_node = var.proxmox_cluster_name
  clone       = var.tamplate_vm_name
  os_type     = "cloud-init"
  agent       = 1
  memory      = var.num_k3s_worker_mem
  cores       = var.number_of_cores
  onboot      = var.start_on_boot
  disk {
    slot            = 0
    size            = var.num_k3s_nodes_worker_storage
    type            = "scsi"
    storage         = "local-lvm"
  }

  ipconfig0 = "ip=${cidrhost("${var.ip_sub}/${var.ip_sub_mask}", var.worker_ip_start+count.index)}/${var.ip_sub_mask},gw=${var.default_gateway}"

}

data "template_file" "k8s" {
  template = file("./templates/k8s.tpl")
  vars = {
    k3s_master_ip = "${join("\n", [for instance in proxmox_vm_qemu.proxmox_vm_master : join("", [instance.default_ipv4_address, " ansible_ssh_private_key_file=", var.pvt_key])])}"
    k3s_node_ip   = "${join("\n", [for instance in proxmox_vm_qemu.proxmox_vm_workers : join("", [instance.default_ipv4_address, " ansible_ssh_private_key_file=", var.pvt_key])])}"
  }
}

resource "local_file" "k8s_file" {
  content  = data.template_file.k8s.rendered
  filename = "inventory/hosts.ini"
}

output "Master-IPS" {
  value = ["${proxmox_vm_qemu.proxmox_vm_master.*.default_ipv4_address}"]
}
output "worker-IPS" {
  value = ["${proxmox_vm_qemu.proxmox_vm_workers.*.default_ipv4_address}"]
}
