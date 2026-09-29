variable "project_prefix" {
  description = "Prefix used for naming all resources in this module"
  type        = string
}

variable "redshift_workgroup" {
  description = "Redshift Serverless workgroup name the Lambda writes to"
  type        = string
}

variable "redshift_database" {
  description = "Redshift Serverless database name the Lambda writes to"
  type        = string
}