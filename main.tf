provider "aws" {
  region = var.aws_region
}

# ---------------------------
# 1. New VPC
# ---------------------------
resource "aws_vpc" "supermario_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "supermario-vpc"
  }
}

# ---------------------------
# 2. Public Subnets in 3 AZs
# ---------------------------
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.supermario_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.supermario_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
  }
}

resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = aws_vpc.supermario_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-2c"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-c"
  }
}

# ---------------------------
# 3. Internet Gateway
# ---------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.supermario_vpc.id

  tags = {
    Name = "supermario-igw"
  }
}

# ---------------------------
# 4. Public Route Table
# ---------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.supermario_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.public_rt.id
}

# ---------------------------
# 5. EKS Cluster & Node Group
# ---------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.2"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  vpc_id     = aws_vpc.supermario_vpc.id
  subnet_ids = [
    aws_subnet.public_subnet_a.id,
    aws_subnet.public_subnet_b.id,
    aws_subnet.public_subnet_c.id
  ]

  eks_managed_node_groups = {
    game_nodes = {
      min_size       = 1
      max_size       = 2
      desired_size   = 2
      instance_types = ["t3.medium"]
      ami_type       = "AL2_x86_64"
      capacity_type  = "ON_DEMAND"
      subnet_ids     = [
        aws_subnet.public_subnet_a.id,
        aws_subnet.public_subnet_b.id,
        aws_subnet.public_subnet_c.id
      ]
    }
  }
}


# ---------------------------
# 6. Kubernetes Provider
# ---------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# ---------------------------
# 7. Super Mario Deployment
# ---------------------------
resource "kubernetes_deployment" "supermario" {
  depends_on = [module.eks]

  metadata {
    name      = "supermario"
    namespace = "default"
    labels = {
      app = "supermario"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "supermario"
      }
    }

    template {
      metadata {
        labels = {
          app = "supermario"
        }
      }
      spec {
        container {
          name  = "supermario"
          image = "bharathshetty4/supermario"

          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

# ---------------------------
# 8. Service: LoadBalancer
# ---------------------------
resource "kubernetes_service" "supermario" {
  depends_on = [kubernetes_deployment.supermario]

  metadata {
    name      = "supermario"
    namespace = "default"
  }

  spec {
    selector = {
      app = kubernetes_deployment.supermario.metadata[0].labels.app
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

# ---------------------------
# 9. Outputs
# ---------------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubernetes_endpoint" {
  value = module.eks.cluster_endpoint
}

output "game_access_url" {
  value = kubernetes_service.supermario.status[0].load_balancer[0].ingress[0].hostname
}

