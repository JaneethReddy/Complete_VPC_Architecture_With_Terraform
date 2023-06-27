variable "region" {
  type = string
}

variable "vpc_name" {
  type = string
}
variable "vpc_cidr" {                                   #VPC Cidr to be used while creating VPC
  type = string
  default = "10.234.0.0/16"
}

variable "on_premises_ip" {
  type =string
  default = "172.16.50.0/24"
}
variable "availability_zone" {                    #availability zones to be used while creating subbnets
  type = list(string)
  default = null
}

variable "dmz_subnets_cidr" {                     #CIDR for DMZ subnets
  type = list(string)
}

variable "application_subnets_cidr" {             #CIDR for application subnets
  type = list(string)
}

variable "database_subnets_cidr" {              #CIDR for DB subnets
  type = list(string)
}

variable "all_private_ip" {                                 #IP CIDR to which access is allowed from our Application & DB Subnets to Transit Gateway
  type = string
  default = "10.0.0.0/16"
}

variable "transitgw_id" {
  type = string
  
}