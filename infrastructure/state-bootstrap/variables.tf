variable "aws_region" {
  type        = string
  description = "AWS region for the state bucket."
  default     = "ap-southeast-1"
}

variable "project" {
  type        = string
  description = "Lowercase project identifier used in the globally unique bucket name."
  default     = "aura"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project must contain only lowercase letters, numbers, and hyphens."
  }
}
