output "workgroup_name" {
  value = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "database_name" {
  value = var.database_name
}

output "namespace_name" {
  value = aws_redshiftserverless_namespace.this.namespace_name
}