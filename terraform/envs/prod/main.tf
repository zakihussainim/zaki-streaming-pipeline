module "redshift" {
  source         = "../../modules/redshift"
  project_prefix = "zaki-streaming-pipeline-prod"
}

module "streaming_pipeline" {
  source             = "../../modules/streaming-pipeline"
  project_prefix     = "zaki-streaming-pipeline-prod"
  redshift_workgroup = module.redshift.workgroup_name
  redshift_database  = module.redshift.database_name
}