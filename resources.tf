data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az = coalesce(var.availability_zone,data.aws_availability_zones.available.names[*]) #choosing whether to use datasource in the case of no availability zone given as variable

   
  
  dmz_subnet_name = join("/",[ "${var.vpc_name}","/dmzsubnet"])           #creating a local variable for DMZ-Subnet-Name
}
data "aws_ec2_transit_gateway" "tgw" {          #getting info about Transit Gateway  available in our account
  id = "${var.transitgw_id}"
}

resource "aws_vpc" "main" {                 #creating a new vpc
  cidr_block       = "${var.vpc_cidr}"
  instance_tenancy = "default"
  enable_dns_support = true
  enable_dns_hostnames = true
  #assign_generated_ipv6_cidr_block = true
  tags = {
    Name = "${var.vpc_name}"
  }
}

resource "aws_subnet" "dmz_subnets" {                   #creating DMZ Subnets
  count = length(var.dmz_subnets_cidr)                     #no of DMZ subnets to be created
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.dmz_subnet_name}${count.index +1}"  
  }
  cidr_block = element(var.dmz_subnets_cidr,count.index)
  availability_zone = local.az[count.index]
 # pair[0].tags.Name
}

resource "aws_subnet" "application_subnets" {                      #creating application Subnets
  count = length(var.application_subnets_cidr)                    #no of application subnets to be created
  vpc_id = aws_vpc.main.id
  tags = {
    Name = join("/",[ "${var.vpc_name}","applicationsubnet${count.index + 1}"])  
  }
  cidr_block = element(var.application_subnets_cidr,count.index)
  availability_zone = local.az[count.index]
}

resource "aws_subnet" "db_subnets" {                                           #creating DB Subnets
  count = length(var.database_subnets_cidr)                                 #no of DB subnets to be created
  vpc_id = aws_vpc.main.id
  tags = {
    Name = join("/",[ "${var.vpc_name}","databasesubnet${count.index + 1}"])  
  }
  cidr_block = element(var.database_subnets_cidr,count.index)
  availability_zone = local.az[count.index]
}

resource "aws_internet_gateway" "igw" {                                        #creating Internet Gateway 
  vpc_id = aws_vpc.main.id

  tags = {
    Name =  "${var.vpc_name}"
  }
}
resource "aws_eip" "eip_for_nat" {                                      #creating Elastic IP to use for NAT Gateway
  count = length(var.dmz_subnets_cidr)
  tags = {
    Name = "${local.dmz_subnet_name}${count.index +1}"  
  }
  vpc      = true
}

resource "aws_nat_gateway" "natgateways" {                    #creating Nat Gateway for application subnets
  count = length(var.dmz_subnets_cidr)
  allocation_id = aws_eip.eip_for_nat[count.index].id
  subnet_id     = aws_subnet.dmz_subnets[count.index].id
  tags = {
    Name = "${local.dmz_subnet_name}${count.index +1}"  
  }
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_vpc_endpoint" "s3" {                      #creating a VPC endpoint to S3 Bucket Service
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  auto_accept = true
  tags = {
    Name = "s3-endpoint-${var.vpc_name}"
  }
}

/* resource "aws_ec2_transit_gateway" "tgw" {
  description = "Transit Gateway for ${var.vpc_name}"
  amazon_side_asn = "64512"
  auto_accept_shared_attachments = enable
  default_route_table_propagation = disable 
  default_route_table_association = disable 
  tags =  {
      Name = "TGW-${var.vpc_name}"
  }
} */

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attach" {                      #attaching our VPC application subnets with transit gateway
  subnet_ids         = [for sn in aws_subnet.application_subnets: sn.id ] #[ for ip in data.openstack_networking_port_v2.ports: ip.all_fixed_ips[0]]
  transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.main.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
}

resource "aws_route_table" "dmz_route_table" {                                                #creating routetable & routes for dmz subnet 
  count = length(var.dmz_subnets_cidr)
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  route {
    cidr_block = "${var.all_private_ip}"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  } 
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.tgw_attach] 
  tags = {
    Name = "${local.dmz_subnet_name}${count.index +1}"  
  }
}

resource "aws_route_table" "application_route_table" {                      #creating routetable & routes for application subnet 
  count = length(var.application_subnets_cidr)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgateways[count.index].id
  }

  route {
    cidr_block = "${var.all_private_ip}"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  } 
  route {
    cidr_block = "${var.on_premises_ip}"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.tgw_attach] 

 
  tags = {
     Name = join("/",[ "${var.vpc_name}","applicationsubnet${count.index + 1}"])
  }
}

resource "aws_route_table" "database_route_table" {                           #creating routetable & routes for DB subnet 
  count = length(var.database_subnets_cidr)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "${var.all_private_ip}"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }
    route {
    cidr_block = "${var.on_premises_ip}"
    transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id
  }
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.tgw_attach]
  
  
  tags = {
    Name = join("/",[ "${var.vpc_name}","databasesubnet${count.index + 1}"])  
  }

}

resource "aws_route_table_association" "dmz_route_table_association" {                                  #Associating DMZ subnets with DMZ related RouteTable
 count = length(var.dmz_subnets_cidr)
  subnet_id      = aws_subnet.dmz_subnets[count.index].id
  route_table_id = aws_route_table.dmz_route_table[count.index].id
}

resource "aws_route_table_association" "application_route_table_association" {                    #Associating application subnets with application related RouteTable
  count = length(var.application_subnets_cidr)
  subnet_id      = aws_subnet.application_subnets[count.index].id
  route_table_id = aws_route_table.application_route_table[count.index].id
}

resource "aws_route_table_association" "database_route_table_association" {                       #Associating DB subnets with DB related RouteTable
  count = length(var.database_subnets_cidr)
  subnet_id      = aws_subnet.db_subnets[count.index].id
  route_table_id = aws_route_table.database_route_table[count.index].id
}

