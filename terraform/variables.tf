variable "region" {
  description = "AWS Region that holds every resource in this stack."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name in this stack."
  type        = string
  default     = "serverless-pipeline"
}

# variable "alert_email" {
#   description = "Address the budget alert is delivered to. No default: export TF_VAR_alert_email."
#   type        = string
# }
