variable "aws_region" {
  type        = string
  description = "Approved Release 1 AWS region."
  default     = "ap-southeast-1"
}

variable "project" {
  type        = string
  description = "Lowercase project identifier."
  default     = "aura"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name. Use a separate state key and tfvars file for staging and production."

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "budget_alert_email" {
  type        = string
  description = "Owner email for AWS Budget notifications. Keep this only in secure tfvars."
  sensitive   = true
}

variable "github_repository" {
  type        = string
  description = "GitHub repository permitted to assume the environment deployment role."
  default     = "mindu2kk/Internship"
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "Existing GitHub Actions OIDC provider ARN. Set this in the second environment state so the account-level provider is not created twice."
  default     = null
}

variable "instance_type" {
  type        = string
  description = "Selected x86_64 Release 1 candidate. t3.small is the same-memory fallback when a Free Tier account rejects t3a.small."
  default     = "t3a.small"

  validation {
    condition     = contains(["t3a.small", "t3.small"], var.instance_type)
    error_message = "Release 1 permits only t3a.small or the same-memory x86_64 t3.small fallback."
  }
}

variable "root_volume_size_gib" {
  type        = number
  description = "Encrypted gp3 root/data capacity. The host binds /srv/aura/data into containers."
  default     = 20

  validation {
    condition     = var.root_volume_size_gib >= 20 && var.root_volume_size_gib <= 30
    error_message = "root_volume_size_gib must remain within the approved 20-30 GiB cost envelope."
  }
}

variable "backup_retention_days" {
  type        = number
  description = "Retention for compact daily S3 backups."
  default     = 30
}

variable "cloudflare_tunnel_parameter_name" {
  type        = string
  description = "Out-of-state SSM SecureString holding the Cloudflare named-tunnel token."
  default     = null
}

variable "runtime_secret_parameter_names" {
  type        = map(string)
  description = "Maps application environment names to SecureString leaf names under the environment prefix. Terraform never manages their values."
  default = {
    API_BEARER_TOKEN    = "api_bearer_token"
    GOOGLE_API_KEY      = "google_api_key"
    OPENAI_API_KEY      = "openai_api_key"
    TAVILY_API_KEY      = "tavily_api_key"
    LLAMA_CLOUD_API_KEY = "llama_cloud_api_key"
  }
}
