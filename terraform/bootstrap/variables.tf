variable "region" {
  description = "Region the state bucket lives in"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Name of the bucket that holds every stack's state"
  type        = string
}
