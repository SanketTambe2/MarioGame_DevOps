variable "aws_region" {
  default     = "us-east-2"
  description = "AWS region"
}

variable "cluster_name" {
  default     = "supermario-cluster"
  description = "EKS cluster name"
}

variable "cluster_version" {
  default     = "1.28"
  description = "EKS Kubernetes version"
}

