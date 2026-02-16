variable "keys" {
  description = "Map of KMS keys to create"
  type = map(object({
    alias                  = string
    description            = optional(string, "")
    deletion_window_in_days = optional(number, 30)
    enable_key_rotation    = optional(bool, true)
    policy                 = optional(string)
    tags                   = optional(map(string), {})
  }))
  default = {}
}