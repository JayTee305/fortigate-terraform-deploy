#### External Load Balancer ###
### Forwarding Rule ###
resource "google_compute_forwarding_rule" "default" {
  name       = "external-lb-${random_string.random_name_post.result}"
  region     = var.region
  ip_address = google_compute_address.static.address

  load_balancing_scheme = "EXTERNAL"
  target                = google_compute_target_pool.default.self_link
}

### Target Pools ###
resource "google_compute_target_pool" "default" {
  name             = "fgt-instancepool-${random_string.random_name_post.result}"
  region           = var.region
  session_affinity = "CLIENT_IP"

  #instances = [
  #  "${var.zone}/fgt-2-${random_string.random_name_post.result}",
  #  "${var.zone}/fgt-${random_string.random_name_post.result}"
  #]

  instances = [google_compute_instance_from_template.active_fgt_instance.self_link, google_compute_instance_from_template.passive_fgt_instance.self_link]

  health_checks = [
    google_compute_http_health_check.default.name
  ]
}

### Health Check ###
resource "google_compute_http_health_check" "default" {
  name                = "health-check-backend-${random_string.random_name_post.result}"
  check_interval_sec  = 3
  timeout_sec         = 2
  unhealthy_threshold = 3
  port                = "8008"
}



### Internal ###
resource "google_compute_address" "internal_address" {
  name         = "internal-ilb-address-${random_string.random_name_post.result}"
  subnetwork   = google_compute_subnetwork.private_subnet.self_link
  address_type = "INTERNAL"
  address      = cidrhost(var.protected_subnet, 5)
  region       = var.region
}

resource "google_compute_forwarding_rule" "internal_load_balancer" {
  name       = "internal-slb-${random_string.random_name_post.result}"
  region     = var.region
  ip_address = google_compute_address.internal_address.address

  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.internal_load_balancer_backend.self_link
  all_ports             = true
  network               = google_compute_network.vpc_network2.self_link
  subnetwork            = google_compute_subnetwork.private_subnet.self_link
}

resource "google_compute_region_backend_service" "internal_load_balancer_backend" {
  name                            = "internal-slb-backend-${random_string.random_name_post.result}"
  region                          = var.region
  connection_draining_timeout_sec = 10
  session_affinity                = "CLIENT_IP"
  network                         = google_compute_network.vpc_network2.self_link


  backend {
    group = google_compute_instance_group.umig_active.self_link
  }

  backend {
    group = google_compute_instance_group.umig_passive.self_link
  }

  health_checks = [
    google_compute_health_check.hc.self_link
  ]
}

resource "google_compute_health_check" "hc" {
  name               = "internal-slb-healthcheck-${random_string.random_name_post.result}"
  check_interval_sec = 3
  timeout_sec        = 2
  tcp_health_check {
    port = "8008"
  }
}

# Active FGT Instance template
resource "google_compute_instance_template" "active" {
  name        = "active-fgt-template-${random_string.random_name_post.result}"
  description = "FGT-Active Instance Template"

  instance_description = "FGT-Active Instance Template"
  machine_type         = var.machine
  can_ip_forward       = true

  tags = ["allow-fgt", "allow-internal", "allow-sync", "allow-mgmt"]

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  # Create a new boot disk from an image
  disk {
    source_image = var.image
    auto_delete  = true
    boot         = true
  }

  # Log Disk
  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = 30
  }

  # Public Network
  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.name
    network_ip = var.active_port1_ip
    # access_config {}
  }

  # Private Network
  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.name
    network_ip = var.active_port2_ip
  }

  # HA Sync Network
  network_interface {
    subnetwork = google_compute_subnetwork.ha_subnet.name
    network_ip = var.active_port3_ip
  }

  # Mgmt Network
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt_subnet.name
    network_ip = var.active_port4_ip
    access_config {
      nat_ip = google_compute_address.static2.address
    }
  }

  # Metadata to bootstrap FGT
  metadata = {
    user-data              = "${data.template_file.setup-active.rendered}"
    license                = fileexists("${path.module}/${var.licenseFile}") ? "${file(var.licenseFile)}" : null
    block-project-ssh-keys = "TRUE"
  }

  # Email will be the service account
  service_account {
    scopes = ["userinfo-email", "compute-rw", "storage-ro", "cloud-platform"]
  }
}


# Compute template for passive node
#
resource "google_compute_instance_template" "passive" {
  name        = "passive-fgt-template-${random_string.random_name_post.result}"
  description = "FGT-Passive Instance Template"

  instance_description = "FGT-Passive Instance Template"
  machine_type         = var.machine
  can_ip_forward       = true

  tags = ["allow-fgt", "allow-internal", "allow-sync", "allow-mgmt"]

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  # Create a new boot disk from an image
  disk {
    source_image = var.image
    auto_delete  = true
    boot         = true
  }

  # Log Disk
  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = 30
  }

  # Public Network
  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.name
    network_ip = var.passive_port1_ip
  }

  # Private Network
  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.name
    network_ip = var.passive_port2_ip
  }

  # HA Sync Network
  network_interface {
    subnetwork = google_compute_subnetwork.ha_subnet.name
    network_ip = var.passive_port3_ip
  }

  # Mgmt Network
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt_subnet.name
    network_ip = var.passive_port4_ip
    access_config {
      nat_ip = google_compute_address.static3.address
    }
  }

  metadata = {
    user-data              = "${data.template_file.setup-passive.rendered}"
    license                = fileexists("${path.module}/${var.licenseFile2}") ? "${file(var.licenseFile2)}" : null
    block-project-ssh-keys = "TRUE"
  }
  service_account {
    scopes = ["userinfo-email", "compute-rw", "storage-ro", "cloud-platform"]
  }
}


#
# FGT Active FGT
#
resource "google_compute_instance_from_template" "active_fgt_instance" {
  name                     = "activefgt-${random_string.random_name_post.result}"
  zone                     = var.zone
  source_instance_template = google_compute_instance_template.active.self_link

  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.name
    network_ip = var.active_port1_ip
  }
  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.name
    network_ip = var.active_port2_ip
  }
  network_interface {
    subnetwork = google_compute_subnetwork.ha_subnet.name
    network_ip = var.active_port3_ip
  }
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt_subnet.name
    network_ip = var.active_port4_ip
    access_config {
      nat_ip = google_compute_address.static2.address
    }
  }
}

#
# FGT Passive FGT
#
resource "google_compute_instance_from_template" "passive_fgt_instance" {
  depends_on               = [google_compute_instance_from_template.active_fgt_instance]
  name                     = "passivefgt-${random_string.random_name_post.result}"
  zone                     = var.zone
  source_instance_template = google_compute_instance_template.passive.self_link

  network_interface {
    subnetwork = google_compute_subnetwork.public_subnet.name
    network_ip = var.passive_port1_ip
  }
  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.name
    network_ip = var.passive_port2_ip
  }
  network_interface {
    subnetwork = google_compute_subnetwork.ha_subnet.name
    network_ip = var.passive_port3_ip
  }
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt_subnet.name
    network_ip = var.passive_port4_ip
    access_config {
      nat_ip = google_compute_address.static3.address
    }
  }
}

###########################
# UnManaged Instance Group
###########################
resource "google_compute_instance_group" "umig_active" {
  name    = "unmanage-active-${random_string.random_name_post.result}"
  project = var.project
  zone    = var.zone
  instances = matchkeys(
    google_compute_instance_from_template.active_fgt_instance.*.self_link,
    google_compute_instance_from_template.active_fgt_instance.*.zone,
    [var.zone],
  )
}

resource "google_compute_instance_group" "umig_passive" {
  name    = "unmanage-passive-${random_string.random_name_post.result}"
  project = var.project
  zone    = var.zone
  instances = matchkeys(
    google_compute_instance_from_template.passive_fgt_instance.*.self_link,
    google_compute_instance_from_template.passive_fgt_instance.*.zone,
    [var.zone],
  )
}
