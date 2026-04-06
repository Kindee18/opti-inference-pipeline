output "cluster_name"    { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "ecr_url"          { value = module.ecr.repository_url }
output "sqs_queue_url"    { value = module.iam.sqs_queue_url }
