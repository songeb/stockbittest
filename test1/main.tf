# Creating VPC here
resource "aws_vpc" "vpc" {                
   cidr_block       = var.vpc_cidr        # Defining the CIDR block use 10.0.0.0/24
   instance_tenancy = "default"
   enable_dns_hostnames = true
   enable_dns_support   = true
 }

# Creating Internet Gateway
 resource "aws_internet_gateway" "igw" {    
    vpc_id =  aws_vpc.vpc.id                
    depends_on = [aws_vpc.vpc]
 }

 # Create a Public Subnets
 resource "aws_subnet" "public_subnet" {    
   vpc_id =  aws_vpc.vpc.id
   cidr_block = "${var.public_subnet}"      # CIDR block of public subnets
 }

 # Create a Private Subnet                 
 resource "aws_subnet" "private_subnet" {
   vpc_id =  aws_vpc.vpc.id
   cidr_block = "${var.private_subnet}"     # CIDR block of private subnets
 }

 # Creating Route Table for Public Subnet
 resource "aws_route_table" "public_route" {    
    vpc_id =  aws_vpc.vpc.id
    route {
      cidr_block = "${var.internet_cidr}"               # Traffic from Public Subnet reaches Internet via Internet Gateway
      gateway_id = aws_internet_gateway.igw.id
    }
 }

 # Creating Route Table for Private Subnet
 resource "aws_route_table" "private_route" {    
   vpc_id = aws_vpc.vpc.id
   route {
   cidr_block = "${var.internet_cidr}"             # Traffic from Private Subnet reaches Internet via NAT Gateway
   nat_gateway_id = aws_nat_gateway.nat_gw.id
   }
 }

 # Creating Route table Association with Public Subnet
 resource "aws_route_table_association" "public_route_assoc" {
    subnet_id = aws_subnet.public_subnet.id
    route_table_id = aws_route_table.public_route.id
 }

 # Creating Route table Association with Private Subnet
 resource "aws_route_table_association" "private_route_assoc" {
    subnet_id = aws_subnet.private_subnet.id
    route_table_id = aws_route_table.private_route.id
 }


 resource "aws_eip" "nat_elastic_ip" {
   vpc   = true
   depends_on = [aws_internet_gateway.igw]
 }
 
 # Creating the NAT Gateway using subnet_id and allocation_id
 resource "aws_nat_gateway" "nat_gw" {
   allocation_id = aws_eip.nat_elastic_ip.id
   subnet_id = aws_subnet.public_subnet.id
   depends_on    = [aws_internet_gateway.igw]
 }


 resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc.id

  ingress = [
    {
      description = "Allow inbound traffic"
      protocol  = -1
      self      = true
      from_port = 0
      to_port   = 0
      cidr_blocks = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
    }
  ]

  egress = [
    {
      description = "Allow outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self      = true
    }
  ]
  depends_on = [aws_vpc.vpc]
}

# this will create a key with RSA algorithm with 4096 rsa bits
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# this resource will create a key pair using above private key
resource "aws_key_pair" "key_pair" {
  key_name   = "${var.key_name}"
  public_key = tls_private_key.private_key.public_key_openssh
  depends_on = [tls_private_key.private_key]
}

# this resource will save the private key at our specified path.
resource "local_file" "saveKey" {
  content = tls_private_key.private_key.private_key_pem
  filename = "${var.base_path}${var.key_name}.pem"
  
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# creating aws launch configuration
resource "aws_launch_configuration" "agent-lc" {
    name_prefix = "agent-lc-"
    image_id = data.aws_ami.ubuntu.id
    instance_type = "${var.instance_type}"
    key_name = aws_key_pair.key_pair.key_name
    user_data = <<EOF
            #! /bin/bash
            sudo apt-get update
            sudo apt-get install docker-ce docker-ce-cli containerd.io -y
            sudo systemctl restart docker
            sudo systemctl enable docker
            sudo yum install unzip
            wget https://s3.amazonaws.com/testable-scripts/AwsScriptsMon-0.0.1.zip
            unzip AwsScriptsMon-0.0.1.zip
            rm AwsScriptsMon-0.0.1.zip
            cd aws-scripts-mon
            crontab -l | { cat; echo "*/5 * * * * ~/aws-scripts-mon/mon-put-instance-data.pl --from-cron --auto-scaling --mem-util"; } | crontab - 
  EOF

    lifecycle {
        create_before_destroy = true
    }

    root_block_device {
        volume_type = "gp2"
        volume_size = "50"
    }
}

resource "aws_autoscaling_group" "agents" {
    vpc_zone_identifier = [ aws_subnet.private_subnet.id ]
    name = "agents"
    max_size = "5"
    min_size = "2"
    health_check_grace_period = 300
    health_check_type = "EC2"
    desired_capacity = 2
    force_delete = true
    launch_configuration = "${aws_launch_configuration.agent-lc.name}"

    tag {
        key = "Name"
        value = "Agent Instance"
        propagate_at_launch = true
    }
}

resource "aws_autoscaling_policy" "agents-scale-up" {
    name = "agents-scale-up"
    scaling_adjustment = 1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.agents.name}"
}

resource "aws_autoscaling_policy" "agents-scale-down" {
    name = "agents-scale-down"
    scaling_adjustment = -1
    adjustment_type = "ChangeInCapacity"
    cooldown = 300
    autoscaling_group_name = "${aws_autoscaling_group.agents.name}"
}

resource "aws_cloudwatch_metric_alarm" "memory-high" {
    alarm_name = "mem-util-high-agents"
    comparison_operator = "GreaterThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "MemoryUtilization"
    namespace = "System/Linux"
    period = "300"
    statistic = "Average"
    threshold = "45"
    alarm_description = "This metric monitors ec2 memory for high utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-up.arn}"
    ]
    dimensions = {
        AutoScalingGroupName = "${aws_autoscaling_group.agents.name}"
    }
}

resource "aws_cloudwatch_metric_alarm" "memory-low" {
    alarm_name = "mem-util-low-agents"
    comparison_operator = "LessThanOrEqualToThreshold"
    evaluation_periods = "2"
    metric_name = "MemoryUtilization"
    namespace = "System/Linux"
    period = "300"
    statistic = "Average"
    threshold = "20"
    alarm_description = "This metric monitors ec2 memory for low utilization on agent hosts"
    alarm_actions = [
        "${aws_autoscaling_policy.agents-scale-down.arn}"
    ]
    dimensions = {
        AutoScalingGroupName = "${aws_autoscaling_group.agents.name}"
    }
}