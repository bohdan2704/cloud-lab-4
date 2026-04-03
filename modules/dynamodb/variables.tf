variable "table_name" {
  description = "The name of the DynamoDB table."
  type        = string
}

variable "hash_key" {
  description = "The partition key used by the DynamoDB table."
  type        = string
  default     = "id"
}

variable "tags" {
  description = "Tags applied to the DynamoDB table."
  type        = map(string)
  default     = {}
}
