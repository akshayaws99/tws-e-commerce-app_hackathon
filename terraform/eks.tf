############################################################
# SECURITY GROUP FOR NODE GROUP REMOTE ACCESS
############################################################
resource "aws_security_group" "node_group_remote_access" {
  name   = "allow-ssh"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################################
# EKS CLUSTER MODULE
############################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                    = local.name
  cluster_version                 = "1.31"
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  ##########################################################
  # ACCESS ENTRIES (ROOT + TERRAFORM IAM USER)
  ##########################################################
  access_entries = {
    terraform = {
      principal_arn = "arn:aws:iam::876997124628:user/terraform"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    root = {
      principal_arn = "arn:aws:iam::460722568558:root"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  ##########################################################
  # CLUSTER SECURITY GROUP RULES
  ##########################################################
  cluster_security_group_additional_rules = {
    access_for_bastion_jenkins_hosts = {
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow all HTTPS traffic from Jenkins and Bastion host"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      type        = "ingress"
    }
  }

  ##########################################################
  # ADDONS
  ##########################################################
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  ##########################################################
  # VPC CONFIG
  ##########################################################
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  ##########################################################
  # NODE GROUP DEFAULTS
  ##########################################################
  eks_managed_node_group_defaults = {
    instance_types = ["t3.large"]
    attach_cluster_primary_security_group = true
  }

  ##########################################################
  # NODE GROUP DEFINITION
  ##########################################################
  eks_managed_node_groups = {
    tws-demo-ng = {
      min_size     = 1
      max_size     = 3
      desired_size = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"

      disk_size                  = 35
      use_custom_launch_template = false # Important to apply disk size!

      remote_access = {
        ec2_ssh_key               = aws_key_pair.deployer.key_name
        source_security_group_ids = [aws_security_group.node_group_remote_access.id]
      }

      tags = {
        Name        = "tws-demo-ng"
        Environment = "dev"
        ExtraTag    = "e-commerce-app"
      }
    }
  }

  tags = local.tags
}

############################################################
# GET EKS NODE INSTANCES
############################################################
data "aws_instances" "eks_nodes" {
  instance_tags = {
    "eks:cluster-name" = module.eks.cluster_name
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [module.eks]
}
