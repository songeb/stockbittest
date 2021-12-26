
  
variable "region" {
    default = "ap-southeast-1"
}
 variable "vpc_cidr" {}
 variable "public_subnet" {}
 variable "private_subnet" {}

 variable "internet_cidr" {}

 # key variable for refrencing 
variable "key_name" {
    default = "ec2Key"
}

# base_path for refrencing 
variable "base_path" {
  default = "/home/bambangdsanjaya/devops/stockbit-test/"
}

variable "instance_count" {}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-07ef508d01f533f5f"
}