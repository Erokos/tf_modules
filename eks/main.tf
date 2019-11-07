provider "aws" {
  region = "${var.region_name}"
}

module "eks_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version              = "v1.67.0"

  name                 = "eks-staging-vpc"
  cidr                 = "10.0.0.0/16"

  azs                  = ["eu-central-1a", "eu-central-1b"]
  private_subnets      = ["10.0.0.0/18", "10.0.64.0/18"]
  public_subnets       = ["10.0.128.0/18", "10.0.192.0/18"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  
  #  reuse_nat_ips        = "${var.eks-reuse-eip}"
  enable_vpn_gateway   = false

  #  external_nat_ip_ids  = ["${var.eks-nat-fixed-eip}"]
  enable_dns_hostnames = true

  tags = {
    Terraform          = "true"
    Environment        = "${terraform.workspace}"
    # Required for EKS and Kubernetes to discover and manage networking resources
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "TCP"
  security_group_id = "${module.eks_vpc.default_security_group_id}"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eks_vpc_allow_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  security_group_id = "${module.eks_vpc.default_security_group_id}"
  cidr_blocks       = ["0.0.0.0/0"]
}

module "eks" {
  source                             = "github.com/Erokos/terraform_modules//eks?ref=417cb77"
  eks_cluster_name                   = "gdna-cluster"
  source_security_group_id           = "${module.eks_vpc.default_security_group_id}"
  vpc_id                             = "${module.eks_vpc.vpc_id}"
  vpc_zone_identifier                = "${module.eks_vpc.private_subnets}"
  worker_launch_template_mixed_count = 2
  cluster_kubernetes_version         = "1.13"
  bastion_vpc_zone_identifier        = "${module.eks_vpc.public_subnets}"
  eks_worker_subnets                 = "${module.eks_vpc.private_subnets}"
  key_name                           = "${var.key_name}"
  key_value                          = "${var.key_value}"

  worker_launch_template_lst = [
    {
      name                       = "general-purpose"
      instance_type_pool1        = "t2.micro"
      instance_type_pool2        = "t3.micro"
      instance_type_pool3        = "t3.nano"
      spot_instance_pools        = 3
      asg_max_size               = 3
      asg_desired_capacity       = 2
      kubelet_extra_args         = "lifecycle=spot,worker-type=general-purpose"
      on_demand_base_capacity    = 0
      instance_shutdown_behavior = "terminate"
      enable_monitoring          = false
      key_name                   = "${var.key_name}"
      key_value                  = "${var.key_value}"
      ebs_optimized              = false
      #eks_ami_id                 = "ami-0c5d8b180f6256839"
    },

    {
      name                       = "compute-optimized"
      instance_type_pool1        = "c5.large"
      instance_type_pool2        = ""
      instance_type_pool3        = ""
      spot_instance_pools        = 1
      asg_max_size               = 1
      asg_desired_capacity       = 1
      kubelet_extra_args         = "lifecycle=spot,worker-type=compute-optimized"
      on_demand_base_capacity    = 0
      instance_shutdown_behavior = "terminate"
      enable_monitoring          = false
      key_name                   = "${var.key_name}"
      key_value                  = "${var.key_value}"
      ebs_optimized              = false
      #eks_ami_id                 = "ami-0c5d8b180f6256839"
    }
  ]
}