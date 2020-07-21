provider "aws" {
  profile = "adil"
  region  = "ap-south-1"
}
resource "tls_private_key" "keypair" {
  algorithm = "RSA"
}
module "key_pair" {
  source     = "terraform-aws-modules/key-pair/aws"
  key_name   = "key9"
  public_key = tls_private_key.keypair.public_key_openssh
}
resource "aws_vpc" "myvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true

  tags = {
    Name = "adil_vpc"
  }
}
resource "aws_internet_gateway" "mygw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "adil_gw"
  }
}
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "adil_subnet1"
  }
}
resource "aws_subnet" "private" {
    vpc_id = aws_vpc.myvpc.id

    cidr_block = "192.168.0.0/24"
    availability_zone = "ap-south-1b"

  tags = {
    Name = "adil_subnet2"
  }
}
resource "aws_route_table" "my_route_table1" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mygw.id
  }

  tags = {
    Name = "adil_routetable"
  }
}
resource "aws_route_table_association" "my_route_table_association1" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.my_route_table1.id
}
resource "aws_eip" "my_nat" {
  vpc      = true
  depends_on = [aws_internet_gateway.mygw,]
  
}
resource "aws_nat_gateway" "adil_nat_gw" {
  allocation_id = aws_eip.my_nat.id
  subnet_id     = aws_subnet.public.id
  depends_on = [aws_internet_gateway.mygw,]
 
 tags = {
    Name = "adil nat_gw"
  }
}
resource "aws_route_table" "my_route_table2" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.adil_nat_gw.id
  }

  tags = {
    Name = "adil_routetable_for_natgw"
  }
}

resource "aws_route_table_association" "route_table_association2" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.my_route_table2.id
}
resource "aws_security_group" "mywebsecurity" {
  name        = "my_web_security"
  description = "Allow http,ssh,icmp"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ALL ICMP - IPv4"
    from_port   = -1    
    to_port     = -1
    protocol    = "ICMP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "my_web_sg"
  }
} 
resource "aws_security_group" "mysqlsecurity" {
  name        = "my_sql_security"
  description = "Allow mysql"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "MYSQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = ["${aws_security_group.mywebsecurity.id}"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "my_sql_sg"
  }
}
resource "aws_security_group" "mybastionsecurity" {
  name        = "my_bastion_security"
  description = "Allow ssh for bastion host"
  vpc_id      = aws_vpc.myvpc.id


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "my_bastion_sg"
  }
} 
resource "aws_security_group" "mysqlserversecurity" {
  name        = "my_sql_server_security"
  description = "Allow mysql ssh for bastion host only"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = ["${aws_security_group.mybastionsecurity.id}"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "my_sql_server_sg"
  }
}

resource "aws_instance" "wordpress" {
  ami           = "ami-000cbce3e1b899ebd"
  instance_type = "t2.micro"
  associate_public_ip_address = true
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = ["${aws_security_group.mywebsecurity.id}"]
  key_name = "key9"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "wordpress"
  }

}
resource "aws_instance" "mysql" {
  ami           = "ami-08706cb5f68222d09"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.private.id
  vpc_security_group_ids = ["${aws_security_group.mysqlsecurity.id}","${aws_security_group.mysqlserversecurity.id}"]
  key_name = "key9"
  availability_zone = "ap-south-1b"

 tags = {
    Name = "mysql"
  }

}
resource "aws_instance" "bastionhost" {
  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  associate_public_ip_address = true
  subnet_id = aws_subnet.public.id
  vpc_security_group_ids = ["${aws_security_group.mybastionsecurity.id}"]
  key_name = "key9"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "mybastionhost"
  }
}