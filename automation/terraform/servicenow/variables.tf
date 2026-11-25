# Active brooks-lab instance and its automation credentials. Export them from vars/secrets.yaml
# with scripts/sn-env.sh (prints export lines; use: eval "$(scripts/sn-env.sh)").
variable "SN_URL" {
  description = "Base URL of the active ServiceNow instance (SN_INSTANCES[].url)"
  type        = string
}

variable "SN_USER" {
  description = "ServiceNow automation user (vars/secrets.yaml servicenow.SN_USER<suffix>)"
  type        = string
}

variable "SN_PASSWORD" {
  description = "ServiceNow automation password"
  type        = string
  sensitive   = true
}
