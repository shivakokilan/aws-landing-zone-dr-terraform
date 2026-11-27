variable "primary_region" {
  description = "Primary AWS production region (UAE - Dubai)"
  type        = string
  default     = "me-central-1"
}

variable "dr_region" {
  description = "Secondary AWS disaster recovery region (India - Mumbai)"
  type        = string
  default     = "ap-south-1"
}

variable "org_prefix" {
  description = "Enterprise prefix for Landing Zone and DR resources"
  type        = string
  default     = "gcc-enterprise-lz"
}

variable "dr_glacier_transition_days" {
  description = "Days before DR replicated objects transition to Glacier Instant Retrieval"
  type        = number
  default     = 30
}
