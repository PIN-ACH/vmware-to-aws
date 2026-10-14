# ─────────────────────────────────────────────────────────────────────────────
# Input variables. Defaults mirror config.yaml; the engine/scripts pass overrides
# via -var or a generated .tfvars so nothing site-specific is hardcoded here.
# ─────────────────────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "project" {
  description = "Project/name prefix for all resources."
  type        = string
  default     = "demo-3tier"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# Subnets are described declaratively; the engine fills this from the discovered
# networks in spec.yaml (name/zone/cidr). Defaults match the sample 3-tier app.
variable "subnets" {
  description = "List of subnets to create: name, cidr, zone (public|private)."
  type = list(object({
    name = string
    cidr = string
    zone = string
  }))
  default = [
    { name = "web", cidr = "10.0.10.0/24", zone = "public" },
    { name = "app", cidr = "10.0.20.0/24", zone = "private" },
    { name = "db", cidr = "10.0.30.0/24", zone = "private" },
  ]
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH into instances (VPC-internal by default)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "default_tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    ManagedBy   = "vmware-to-aws-engine"
    Migration   = "replatform"
    Environment = "demo"
  }
}
