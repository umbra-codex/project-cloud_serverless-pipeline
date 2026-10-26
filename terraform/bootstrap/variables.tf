variable "region" {
  description = "Region the state bucket lives in"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Name of the bucket that holds every stack's state"
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string
  default     = "umbra-codex"
}

variable "github_owner_id" {
  description = "Numeric ID of that owner, which the OIDC subject carries"
  type        = string
  default     = "130619362"
}

variable "github_repo" {
  description = "Repository name"
  type        = string
  default     = "project-cloud_serverless-pipeline"
}

variable "github_repo_id" {
  description = "Numeric ID of the repository, which the OIDC subject carries"
  type        = string
  default     = "1432291037"
}
