# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

data "google_compute_network" "default" {
  name = var.private_network
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = data.google_compute_network.default.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = data.google_compute_network.default.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "main" {
  name             = "pgvector-instance"
  database_version = "POSTGRES_15"
  region           = var.region
  settings {
    # Second-generation instance tiers are based on the machine
    # type. See argument reference below.
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.default.id
      enable_private_path_for_google_cloud_services = true
    }
  }
  depends_on = [google_service_networking_connection.private_vpc_connection]
  deletion_protection = false
}

resource "google_sql_database" "database" {
  name     = "pgvector-database"
  instance = google_sql_database_instance.main.name

  depends_on = [ google_sql_database_instance.main ]
}

resource "random_password" "pwd" {
  length  = 16
  special = false
}

resource "google_sql_user" "cloudsql_user" {
  name     = var.db_user
  instance = google_sql_database_instance.main.name
  password = random_password.pwd.result
}

resource "kubernetes_secret" "secret" {
  metadata {
    name = "db-secret"
    namespace = var.namespace
  }

  data = {
    username = var.db_user
    password = random_password.pwd.result
    database = "pgvector-database"
  }

  type = "kubernetes.io/basic-auth"
}
