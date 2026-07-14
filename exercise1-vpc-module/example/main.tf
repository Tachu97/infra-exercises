module "vpc" {
  source = "../modules/vpc"

  name     = "my-app-prod"
  vpc_cidr = "10.0.0.0/16"

  # Two AZs for high availability
  availability_zones = ["eu-west-1a", "eu-west-1b"]

  # 2 public subnets (load balancers, NAT Gateways)
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

  # 2 private subnets (application servers, databases)
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

  tags = {
    Environment = "production"
    Project     = "my-app"
    CostCenter  = "platform"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID to share with other stacks."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for load balancer configuration."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs for application and database layers."
  value       = module.vpc.private_subnet_ids
}

output "s3_vpc_endpoint_id" {
  description = "S3 Gateway endpoint — S3 traffic stays on the AWS backbone."
  value       = module.vpc.s3_vpc_endpoint_id
}
