terraform {
  required_version = ">= 1.5.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# --- Variables ---------------------------------------------------------------

variable "environment" {
  description = "Nom de l'environnement"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit être dev, staging ou prod."
  }
}

variable "instances" {
  description = "Liste d'instances fictives à générer"
  type        = map(number)
  default = {
    web    = 2
    api    = 1
    worker = 3
  }
}

variable "file_count" {
  description = "Nombre de fichiers à générer avec count"
  type        = number
  default     = 2
}

# --- Locals ------------------------------------------------------------------

locals {
  prefix = "${var.environment}-${random_pet.name.id}"

  tags = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# --- Ressources random -------------------------------------------------------

resource "random_pet" "name" {
  length = 2
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_password" "db" {
  length  = 16
  special = true
}

resource "random_integer" "port" {
  for_each = var.instances

  min = 8000
  max = 8999

  keepers = {
    name = each.key
  }
}

# --- Fichiers locaux ---------------------------------------------------------

resource "local_file" "config" {
  filename = "${path.module}/output/config.json"
  content = jsonencode({
    name     = local.prefix
    suffix   = random_id.suffix.hex
    tags     = local.tags
    services = { for k, v in var.instances : k => { replicas = v, port = random_integer.port[k].result } }
  })
}

resource "local_sensitive_file" "secret" {
  filename = "${path.module}/output/secret.txt"
  content  = random_password.db.result
}

resource "local_file" "numbered" {
  count = var.file_count

  filename = "${path.module}/output/file-${count.index}.txt"
  content  = "Fichier ${count.index} pour ${local.prefix}\n"
}

# --- null / terraform_data ---------------------------------------------------

resource "null_resource" "hook" {
  triggers = {
    config_hash = local_file.config.content_md5
  }

  provisioner "local-exec" {
    command = "echo 'config modifiée : ${local_file.config.filename}'"
  }
}

resource "terraform_data" "replica" {
  for_each = var.instances

  input = {
    service  = each.key
    replicas = each.value
  }
}

# --- Data source -------------------------------------------------------------

data "local_file" "config_readback" {
  filename = local_file.config.filename
}

# --- Check (Terraform >= 1.5) ------------------------------------------------

check "config_not_empty" {
  assert {
    condition     = length(data.local_file.config_readback.content) > 0
    error_message = "Le fichier de config est vide."
  }
}

# --- Outputs -----------------------------------------------------------------

output "prefix" {
  value = local.prefix
}

output "ports" {
  value = { for k, v in random_integer.port : k => v.result }
}

output "files" {
  value = concat([local_file.config.filename], local_file.numbered[*].filename)
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
