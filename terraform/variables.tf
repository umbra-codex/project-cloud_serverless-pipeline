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

variable "alert_email" {
  description = "Address the budget alert is delivered to. No default: export TF_VAR_alert_email."
  type        = string
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for each function. -1 means no reservation."
  type        = number
  default     = -1
}

variable "maximum_concurrency" {
  description = "Maximum concurrency the consumer's event source mapping may use."
  type        = number
  default     = 2
}

variable "budget_limit_usd" {
  description = "Monthly budget limit, in US dollars, as a string."
  type        = string
  default     = "1"
}
