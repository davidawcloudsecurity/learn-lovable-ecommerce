terraform {
  required_version = ">= 1.1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "create_new_role" {
  type        = bool
  default     = true
  description = "Whether to create new role or use existing"
}

variable "existing_role_name" {
  type        = string
  default     = "lambda-execution-role"
  description = "Name of existing role if not creating new one"
}

variable "existing_instance_profile" {
  type        = string
  default     = "ec2_ssm_role"
  description = "Name of existing role if not creating new one"
}

# Check if role exists
data "aws_iam_role" "existing_instance_profile" {
  count = var.create_new_role ? 0 : 1
  name  = var.existing_instance_profile
}

# Add this data source to get the current AWS region
data "aws_region" "current" {}

variable "ami" {
  description = "Amazon Linux 2 AMI ID"
  default     = "ami-02c21308fed24a8ab" # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type in us-east-1
}

variable "ami_ubuntu" {
  description = "ubuntu-jammy-22.04 AMI ID"
  default     = "ami-0a7d80731ae1b2435" # ubuntu-jammy-22.04
}

provider "aws" {
  region  = var.region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/23"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "public_facing_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/26"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1a"
  }
}

resource "aws_subnet" "public_facing_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/26"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1b"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.128/26"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-app-subnet"
  }
}

resource "aws_subnet" "private_app_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.128/26"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-app-subnet-1b"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.192/26"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-db-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}


# NAT Gateway
resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_facing_1a.id

  tags = {
    Name = "main-nat"
  }
}

# Route Tables
resource "aws_route_table" "public_facing" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-facing-route-table"
  }
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-app-route-table"
  }
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-db-route-table"
  }
}

resource "aws_route_table_association" "public_facing" {
  subnet_id      = aws_subnet.public_facing_1a.id
  route_table_id = aws_route_table.public_facing.id
}

# Add missing route table association for public_facing_1b
resource "aws_route_table_association" "public_facing_1b" {
  subnet_id      = aws_subnet.public_facing_1b.id
  route_table_id = aws_route_table.public_facing.id
}

# Add a second private subnet in us-east-1b for high availability
resource "aws_subnet" "private_db_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.192/26"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-db-subnet-1b"
  }
}

# Route table association for the new subnet
resource "aws_route_table_association" "private_db_1b" {
  subnet_id      = aws_subnet.private_db_1b.id
  route_table_id = aws_route_table.private_db.id
}


resource "aws_route_table_association" "private_app" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_app_1b" {
  subnet_id      = aws_subnet.private_app_1b.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_db" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_db.id
}

# Security Groups
resource "aws_security_group" "public_facing" {
  name        = "allow_http_https"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_https"
  }
}

resource "aws_security_group" "private_app" {
  name        = "allow_alb"
  description = "Allow inbound traffic from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from public subnet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    #    cidr_blocks = [aws_security_group.public_facing.id]
    security_groups = [aws_security_group.public_facing.id]
  }

  ingress {
    description = "HTTPS from public subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.public_facing.id]
  }

  ingress {
    description = "MYSQL/Aurora from private subnet"
    from_port   = 3001
    to_port     = 3001
    protocol    = "TCP"
    security_groups = [aws_security_group.public_facing.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_nginx"
  }
}

resource "aws_security_group" "private_db" {
  name        = "allow_backend"
  description = "Allow HTTP inbound traffic within VPC"
  vpc_id      = aws_vpc.main.id
/* Exclude because using api
  ingress {
    description = "HTTP from private subnet app tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    #    cidr_blocks = [aws_security_group.public.id]
    security_groups = [aws_security_group.private_app.id]
  }
*/
  ingress {
    description = "Setup to allow SSM"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
#    cidr_blocks = [aws_security_group.public.id]
    security_groups = [aws_security_group.private_app.id]
  }



  ingress {
    description = "Allow HTTP inbound traffic within VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  } 

  egress {
    description = "Outbound to all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_wordpress"
  }
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "ec2_ssm_role" {
  count = var.create_new_role ? 1 : 0
  name  = "ec2_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Use local to select the right role name and ARN
locals {
  instance_profile_name = var.create_new_role ? aws_iam_role.ec2_ssm_role[0].name : data.aws_iam_role.existing_instance_profile[0].name
  instance_profile_arn  = var.create_new_role ? aws_iam_role.ec2_ssm_role[0].arn : data.aws_iam_role.existing_instance_profile[0].arn
}

# Policy attachment
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = local.instance_profile_name  # Changed from incorrect reference
}

# Instance profile
resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  count = var.create_new_role ? 1 : 0  # Add count to avoid conflicts
  name  = "ec2_ssm_profile"
  role  = local.instance_profile_name  # Changed from incorrect reference
}
/* remove since api gateway and lambda
# ALB
resource "aws_lb" "example" {
  name               = "example-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_facing.id]
  subnets            = [
    aws_subnet.public_facing_1a.id,
    aws_subnet.public_facing_1b.id
  ]

  enable_deletion_protection = false

  tags = {
    Environment = "dev"
  }
}



# WORDPRESS LAUNCH TEMPLATE
resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-"
  image_id      = var.ami_ubuntu
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.private_app.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm_profile.name
  }

  # This enables Spot Instance pricing
  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price                      = "0.02"         # Optional: max price in USD/hour
      spot_instance_type             = "one-time"     # or "persistent"
      instance_interruption_behavior = "terminate"    # or "stop" or "hibernate"
    }
  }

  depends_on = [
    aws_s3_bucket.product_images
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt update -y
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    apt install -y nodejs
    cd
    git clone https://github.com/davidawcloudsecurity/learn-lovable-borderless-trade-sphere.git
    cd learn-lovable-borderless-trade-sphere/
    echo "VITE_S3_BUCKET_URL=https://${aws_s3_bucket.product_images.bucket}.s3.${data.aws_region.current.id}.amazonaws.com" > .env
    npm i;npm run build;npm install -g serve;serve -s dist -l 8080
  EOF
  )
}

# MYSQL LAUNCH TEMPLATE
resource "aws_launch_template" "mysql" {
  name_prefix   = "mysql-"
  image_id      = var.ami_ubuntu
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.private_app.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm_profile.name
  }

  # This enables Spot Instance pricing
  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price                      = "0.02"         # Optional: max price in USD/hour
      spot_instance_type             = "one-time"     # or "persistent"
      instance_interruption_behavior = "terminate"    # or "stop" or "hibernate"
    }
  }

	user_data = base64encode(<<-EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log) 2>&1
set -x

apt update -y
git clone https://github.com/davidawcloudsecurity/learn-lovable-ecommerce.git
cd learn-lovable-ecommerce/

# Replace localhost with actual IP
sed -i "s/localhost/\$(hostname -I | awk '{print \$1}')/g" server.js

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
apt-get install -y nodejs

# Install npm packages
npm install -y express cors
npm install pg @types/pg
npm install dotenv
# adapt your Express app to AWS Lambda's format
npm install @vendia/serverless-express

# If needed, strip the port from the endpoint
RDS_ENDPOINT="${aws_db_instance.sqlserver.endpoint}"
RDS_ENDPOINT=$(echo "$RDS_ENDPOINT" | cut -d: -f1)

# Create .env file
echo "POSTGRES_HOST=$RDS_ENDPOINT" > .env
echo "POSTGRES_DB=wordpress" >> .env
echo "POSTGRES_USER=wordpress" >> .env
echo "POSTGRES_PASSWORD=rootpassword" >> .env

# Install Docker
apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
apt-cache policy docker-ce
apt install -y docker-ce
systemctl start docker
systemctl enable docker

# Wait for Docker to be ready
while ! docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to start..."
  sleep 2
done

# Start PostgreSQL container
docker run -d \
  --name postgres \
  -e POSTGRES_DB=wordpress \
  -e POSTGRES_USER=wordpress \
  -e POSTGRES_PASSWORD=rootpassword \
  -p 5432:5432 \
  postgres:16

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
  if docker exec postgres bash -c "PGPASSWORD=rootpassword pg_isready -h $RDS_ENDPOINT -U wordpress -d wordpress" > /dev/null 2>&1; then
	echo "✅ PostgreSQL is ready!"
	break
  else
	echo "⏳ Attempt $i/30: PostgreSQL not ready yet..."
	sleep 5
  fi
done

# Create products table
docker exec postgres bash -c "PGPASSWORD=rootpassword psql -h $RDS_ENDPOINT -U wordpress -d wordpress -c \"CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    original_price DECIMAL(10,2),
    image VARCHAR(255),
    country VARCHAR(100),
    flag VARCHAR(10),
    rating DECIMAL(3,2),
    reviews INTEGER,
    shipping VARCHAR(255),
    category VARCHAR(100)
);\""

# Insert sample data if 100.MD exists
if [ -f "./100.MD" ]; then
  cat ./100.MD | docker exec -i postgres bash -c "PGPASSWORD=rootpassword psql -h $RDS_ENDPOINT -U wordpress -d wordpress"
fi

# Start the Node.js application
nohup node server.js > /var/log/node-app.log 2>&1 &
	EOF
)
}
*/
/*
# WORDPRESS AUTOSCALING GROUP
resource "aws_autoscaling_group" "wordpress" {
  name                = "wordpress-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.private_app.id]
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.frontend.arn]

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
*/

/* remove asg
# MYSQL AUTOSCALING GROUP
resource "aws_autoscaling_group" "mysql" {
  name                = "mysql-asg"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 2  # Changed to 2 for HA
  vpc_zone_identifier = [
    aws_subnet.private_db.id,
    aws_subnet.private_db_1b.id  # Add second subnet
  ]
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.backend.arn]

  launch_template {
    id      = aws_launch_template.mysql.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "mysql-asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
*/
resource "aws_s3_bucket" "product_images" {
  bucket = "learn-lovable-product-images-${random_id.suffix.hex}"
  force_destroy = true
  tags = {
    Name        = "Product Images"
    Environment = "production"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.product_images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudfront_access" {
  bucket = aws_s3_bucket.product_images.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.s3_oai.iam_arn
        }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.product_images.arn}/*"
      }
    ]
  })
}

# Null resource to download and upload images from GitHub repo to S3
resource "null_resource" "upload_images_to_s3" {

  depends_on = [
    aws_s3_bucket.product_images,
    aws_s3_bucket_policy.cloudfront_access
  ]

  provisioner "local-exec" {
    command = <<-EOT
      pwd
	# First, check if bucket has content
	if ! aws s3 ls "s3://${aws_s3_bucket.product_images.bucket}/assets/images/" &>/dev/null; then
	  # Only upload if bucket is empty
	  if [ -d "../public/assets/images" ]; then
		aws s3 sync ../public/assets/images/ s3://${aws_s3_bucket.product_images.bucket}/assets/images/ \
		  --no-progress \
		  --size-only
		echo "Initial images upload completed"
	  fi
	else
	  echo "Images already exist in bucket - skipping upload"
	fi
	
	# For the website build and deploy
	if ! aws s3 ls "s3://${aws_s3_bucket.product_images.bucket}/index.html" &>/dev/null; then
	  # Only build and deploy if index.html doesn't exist
	  sudo yum update -y
	  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
	  sudo yum install -y nodejs
	  cd /home
	  sudo git clone https://github.com/davidawcloudsecurity/learn-lovable-borderless-trade-sphere.git
	  cd learn-lovable-borderless-trade-sphere/
	  sudo npm i
	  sudo npm run build
	  aws s3 sync dist s3://${aws_s3_bucket.product_images.bucket} \
		--no-progress \
		--size-only
	  cd /home
	  sudo rm -rf learn-lovable-borderless-trade-sphere
	else
	  echo "Website already deployed - skipping build and deploy"
	fi
    EOT
  }
  # Trigger re-execution if bucket changes
  triggers = {
    bucket_name = aws_s3_bucket.product_images.bucket
    timestamp = timestamp()
  }
}

# Self-signed certificate creation
resource "null_resource" "create_self_signed_cert" {
  provisioner "local-exec" {
    command = <<-EOT
      openssl genrsa -out private-key.pem 2048
      openssl req -new -key private-key.pem -out csr.pem -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com"
      openssl x509 -req -in csr.pem -signkey private-key.pem -out certificate.pem -days 365
      aws acm import-certificate \
        --certificate fileb://certificate.pem \
        --private-key fileb://private-key.pem \
        --region ${var.region} \
        --output text > cert_arn.txt
      rm csr.pem
    EOT
  }
  triggers = {
    always_run = timestamp()
  }
}

# Read certificate ARN from file
data "local_file" "cert_arn" {
  filename = "cert_arn.txt"
  depends_on = [null_resource.create_self_signed_cert]
}

# WAF Web ACL
resource "aws_wafv2_web_acl" "alb_waf" {
  name  = "alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "alb-waf"
    sampled_requests_enabled   = true
  }
}

# Associate WAF with ALB (not NLB, as NLB doesn't support WAF)
resource "aws_wafv2_web_acl_association" "alb_waf" {
  resource_arn = aws_lb.example.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_waf.arn
}

# ALB
resource "aws_lb" "example" {
  name               = "example-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_facing.id]
  subnets            = [
    aws_subnet.private_app.id,
    aws_subnet.private_app_1b.id
  ]
  enable_deletion_protection = false
  tags = {
    Environment = "dev"
  }
}

# Network Load Balancer (internet-facing)
resource "aws_lb" "nlb" {
  name               = "example-network-lb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [
    aws_subnet.public_facing_1a.id,
    aws_subnet.public_facing_1b.id
  ]
  enable_deletion_protection = false
  tags = {
    Environment = "dev"
  }
}

resource "aws_lb_target_group" "alb_port_80" {
  name        = "example-alb-80"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "alb"
  health_check {
    enabled             = true
    path                = "/"
    interval            = 30
    timeout             = 6
    unhealthy_threshold = 3
    healthy_threshold   = 3
    matcher             = "200-399"
    protocol            = "HTTP"
  }
}

resource "aws_lb_target_group" "alb_port_443" {
  name        = "example-alb-443"
  port        = 443
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "alb"
  health_check {
    enabled             = true
    path                = "/"
    interval            = 30
    timeout             = 10
    unhealthy_threshold = 3
    healthy_threshold   = 3
    matcher             = "200-399"
    protocol            = "HTTPS"
  }
}

# ALB target group for actual application
resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    enabled             = true
    path                = "/"
    interval            = 36
    timeout             = 35
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}



# NLB Listeners
resource "aws_lb_listener" "nlb_http" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_port_80.arn
  }
}

resource "aws_lb_listener" "nlb_https" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_port_443.arn
  }
}

# ALB Listeners
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      host        = "#{host}"
      path        = "/#{path}"
      query       = "#{query}"
      status_code = "HTTP_302"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = trimspace(data.local_file.cert_arn.content)
  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = "200"
      content_type = "text/html"
      message_body = "<body>\n  <div style=\"width:100%; margin:0 auto;\">\n    <h1>Please connect https://www.example.com</h1>\n  </div>\n</body>\n"
    }
  }
}

# ALB Listener Rules
resource "aws_lb_listener_rule" "host_redirect" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1
  
  action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      host        = "www.example.com"
      path        = "/#{path}"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }
  
  condition {
    host_header {
      values = ["www.example.com", "example.com", "example.org"]
    }
  }
}

resource "aws_lb_listener_rule" "block_config" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 9
  
  action {
    type = "fixed-response"
    fixed_response {
      status_code  = "403"
      content_type = "text/html"
      message_body = "Forbidden"
    }
  }
  
  condition {
    path_pattern {
      values = ["/id/ver/conf", "/id/ver/conf/*"]
    }
  }
}

resource "aws_lb_listener_rule" "swag_fire" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
  
  condition {
    path_pattern {
      values = ["/swg/*", "/swg", "/fire", "/fire/*"]
    }
  }
}

resource "aws_lb_listener_rule" "api_net" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 11
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
  
  condition {
    path_pattern {
      values = ["/api", "/api/*", "/net", "/net/*"]
    }
  }
}

resource "aws_lb_listener_rule" "version_signin" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 12
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
  
  condition {
    path_pattern {
      values = ["/ver", "/sign", "/sign/*"]
    }
  }
}

resource "aws_lb_listener_rule" "block_config_duplicate" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 14
  
  action {
    type = "fixed-response"
    fixed_response {
      status_code  = "403"
      content_type = "text/html"
      message_body = "Forbidden"
    }
  }
  
  condition {
    path_pattern {
      values = ["/id/ver/conf", "/id/ver/conf/*"]
    }
  }
}

# Add a second target group for id service
resource "aws_lb_target_group" "id" {
  name        = "id-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    enabled             = true
    path                = "/"
    interval            = 36
    timeout             = 35
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener_rule" "id_service" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 15
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.id.arn
  }
  
  condition {
    path_pattern {
      values = ["/id", "/id/*"]
    }
  }
}

# NLB target group attachments (ALB as target)
resource "aws_lb_target_group_attachment" "alb_80" {
  target_group_arn = aws_lb_target_group.alb_port_80.arn
  target_id        = aws_lb.example.arn
  port             = 80
}

resource "aws_lb_target_group_attachment" "alb_443" {
  target_group_arn = aws_lb_target_group.alb_port_443.arn
  target_id        = aws_lb.example.arn
  port             = 443
}



# CloudFront Origin Access Identity for S3
resource "aws_cloudfront_origin_access_identity" "s3_oai" {
  comment = "OAI for ${aws_s3_bucket.product_images.bucket}"
}



# CloudFront Distribution with 8 origins and 11 cache behaviors
resource "aws_cloudfront_distribution" "web_distribution" {
  # Origin 1: Widget content
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-widget"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  # Origin 2: Main app content
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-app"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  # Origin 3: Ticket/booking content
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-booking"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  # Origin 4: Maintenance pages
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-maintenance"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  # Origin 5: Wrapper/layout content
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-wrapper"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  # Origin 6: ALB for dynamic content
  origin {
    domain_name = aws_lb.example.dns_name
    origin_id   = aws_lb.example.dns_name
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin 7: Product builds/assets
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-builds"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  # Origin 8: File storage
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "s3-ecommerce-files"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = "ecommerce application"
  price_class     = "PriceClass_All"

  # Default behavior routes to ALB
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_lb.example.dns_name
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "f1986529-a6cf-42db-b5ed-a04413493488"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 1: Widget components
  ordered_cache_behavior {
    path_pattern           = "/components*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-wrapper"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 2: Chat/support
  ordered_cache_behavior {
    path_pattern           = "/chat*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-widget"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 3: Shopping cart/checkout
  ordered_cache_behavior {
    path_pattern           = "/shop/checkout*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-booking"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 4: JavaScript/CSS assets
  ordered_cache_behavior {
    path_pattern           = "/assets*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-app"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 5: Internationalization
  ordered_cache_behavior {
    path_pattern           = "/i18n*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-app"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 6: File downloads
  ordered_cache_behavior {
    path_pattern           = "/downloads/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-files"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 7: Media content
  ordered_cache_behavior {
    path_pattern           = "/media/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-files"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 8: React/Vue apps
  ordered_cache_behavior {
    path_pattern           = "/spa*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-app"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 9: Product catalog builds
  ordered_cache_behavior {
    path_pattern           = "/catalog/builds/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-builds"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "c48e17ea-26d9-4b32-b384-20d6d17d4159"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 10: Root path
  ordered_cache_behavior {
    path_pattern           = "/"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_lb.example.dns_name
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "f1986529-a6cf-42db-b5ed-a04413493488"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  # Cache behavior 11: Catch-all
  ordered_cache_behavior {
    path_pattern           = "/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-ecommerce-app"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    response_headers_policy_id = "f1986529-a6cf-42db-b5ed-a04413493488"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = trimspace(data.local_file.cert_arn.content)
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn

  depends_on = [
    aws_s3_bucket_policy.cloudfront_access
  ]
}

# WAF for CloudFront
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  name  = "waf-ecommerce-cloudfront"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf-ecommerce-cloudfront"
    sampled_requests_enabled   = true
  }
}

/* remove local instance
# EC2 Instances
resource "aws_instance" "nginx" {
  ami                    = var.ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_facing_1a.id
  vpc_security_group_ids = [aws_security_group.public_facing.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker pull nginx
              
              # Create a custom NGINX configuration to point to the WordPress instance
              cat << EOF1 > /home/ec2-user/default.conf
              server {
                  listen 80;
                  server_name localhost;
              
                  location / {
                      proxy_pass http://${aws_instance.wordpress.private_ip}:8080;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto \$scheme;
                  }

                  location /api/ {
                      proxy_pass http://${aws_instance.mysql.private_ip}:3001;
                      proxy_http_version 1.1;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                  }
              }
              EOF1

              docker run -d -p 80:80 --name nginx-demo nginx;
              # Wait until the nginx-demo container is running
              while [ "$(docker inspect -f '{{.State.Running}}' nginx-demo)" != "true" ]; do
                  echo "Waiting for nginx-demo to start..."
                  sleep 1
              done
              docker cp /home/ec2-user/default.conf nginx-demo:/etc/nginx/conf.d;
              docker exec nginx-demo nginx -s reload;
              EOF

  tags = {
    Name = "nginx-instance"
  }
  depends_on = [
      aws_nat_gateway.nat,
      aws_instance.mysql
  ]
}

resource "aws_instance" "wordpress" {
  ami                    = var.ami_ubuntu
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_app.id
  vpc_security_group_ids = [aws_security_group.private_app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
              apt install -y nodejs
              cd
              git clone -b supabase_auth_main https://github.com/davidawcloudsecurity/learn-lovable-borderless-trade-sphere.git
              cd learn-lovable-borderless-trade-sphere/
              npm i;npm run dev
              EOF

  tags = {
    Name = "wordpress-instance"
  }
  depends_on = [
      aws_nat_gateway.nat,
      aws_instance.mysql
  ]
}

resource "aws_instance" "mysql" {
  ami                    = var.ami_ubuntu
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_db.id
  vpc_security_group_ids = [aws_security_group.private_db.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  # This enables Spot Instance pricing
  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price                      = "0.02"         # Optional: max price in USD/hour
      spot_instance_type             = "one-time"     # or "persistent"
      instance_interruption_behavior = "terminate"    # or "stop" or "hibernate"
    }
  }

  user_data = <<-EOF
              #!/bin/bash
              git clone -b supabase_auth_main https://github.com/davidawcloudsecurity/learn-lovable-borderless-trade-sphere.git
              cd learn-lovable-borderless-trade-sphere/
              sed -i "s/localhost/$(hostname -I | awk '{print $1}')/g" server.js
              apt update -y
              curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
              apt-get install -y nodejs
              apt install -y npm
              npm install -y express cors
              node server.js
              apt install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker run -d -e MYSQL_ROOT_PASSWORD=rootpassword \
                         -e MYSQL_DATABASE=wordpress \
                         -e MYSQL_USER=wordpress \
                         -e MYSQL_PASSWORD=wordpress \
                         -p 3306:3306 mysql:5.7
              EOF

  tags = {
    Name = "mysql-instance"
  }
  depends_on = [aws_nat_gateway.nat]
}

output "seeds" {
  value = [aws_instance.nginx.private_ip, aws_instance.wordpress.private_ip, aws_instance.mysql.private_ip]
}
*/

# Check if ECR repository exists
data "aws_ecr_repository" "existing_nginx" {
  name = "nginx-ecommerce"
  count = var.create_new_role ? 0 : 1
}

# ECR Repository for nginx image - create only if needed
resource "aws_ecr_repository" "nginx" {
  count                = var.create_new_role ? 1 : 0
  name                 = "nginx-ecommerce"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }
}

locals {
  nginx_repository_url = var.create_new_role ? aws_ecr_repository.nginx[0].repository_url : data.aws_ecr_repository.existing_nginx[0].repository_url
}

# Build and push nginx image to ECR
resource "null_resource" "nginx_image" {
  depends_on = [aws_ecr_repository.nginx]

  provisioner "local-exec" {
    command = <<-EOT
      cat > ../Dockerfile << 'EOF'
FROM nginx:alpine

RUN apk add --no-cache openssl

RUN mkdir -p /etc/ssl/certs /etc/ssl/private && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

RUN echo 'server { \
    listen 80; \
    listen 443 ssl; \
    server_name localhost; \
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt; \
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html; \
    } \
    location /health { \
        access_log off; \
        return 200 "healthy\\n"; \
        add_header Content-Type text/plain; \
    } \
    location ~ ^/.*/health$ { \
        access_log off; \
        return 200 "healthy\\n"; \
        add_header Content-Type text/plain; \
    } \
}' > /etc/nginx/conf.d/default.conf

COPY . /usr/share/nginx/html
EXPOSE 80 443
EOF
      aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.nginx_repository_url}
      docker build -t nginx-ecommerce ../
      docker tag nginx-ecommerce:latest ${local.nginx_repository_url}:latest
      docker push ${local.nginx_repository_url}:latest
    EOT
  }

  triggers = {
    repository_url = local.nginx_repository_url
  }
}

# Outputs
# Outputs
output "network_lb_dns_name" {
  value = aws_lb.nlb.dns_name
}

output "alb_dns_name" {
  value = aws_lb.example.dns_name
}



output "certificate_arn" {
  value = trimspace(data.local_file.cert_arn.content)
}

# VPC and Networking
output "vpc_id" {
  value = aws_vpc.main.id
}

# App Subnets
output "private_app_subnet_ids" {
  value = [aws_subnet.private_app.id, aws_subnet.private_app_1b.id]
}

# DB Subnets  
output "private_db_subnet_ids" {
  value = [aws_subnet.private_db.id, aws_subnet.private_db_1b.id]
}

# Security Groups
output "security_group_public_facing" {
  value = aws_security_group.public_facing.id
}

output "security_group_private_app" {
  value = aws_security_group.private_app.id
}

output "security_group_private_db" {
  value = aws_security_group.private_db.id
}

# Target Groups
output "target_groups" {
  value = {
    frontend = aws_lb_target_group.frontend.arn
    id = aws_lb_target_group.id.arn
    alb_port_80 = aws_lb_target_group.alb_port_80.arn
    alb_port_443 = aws_lb_target_group.alb_port_443.arn
  }
}

# VPC Endpoint for CloudWatch Logs
resource "aws_security_group" "vpc_endpoints" {
  name        = "vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vpc-endpoints-sg"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  subnet_ids          = [aws_subnet.private_app.id, aws_subnet.private_app_1b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type   = "Interface"
  
  tags = {
    Name = "cloudwatch-logs-endpoint"
  }
}

# Secrets Manager VPC Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  subnet_ids          = [aws_subnet.private_app.id, aws_subnet.private_app_1b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type   = "Interface"
  
  tags = {
    Name = "secretsmanager-endpoint"
  }
}

# ECR VPC Endpoints
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  subnet_ids          = [aws_subnet.private_app.id, aws_subnet.private_app_1b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type   = "Interface"
  
  tags = {
    Name = "ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  subnet_ids          = [aws_subnet.private_app.id, aws_subnet.private_app_1b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  vpc_endpoint_type   = "Interface"
  
  tags = {
    Name = "ecr-api-endpoint"
  }
}

# S3 Gateway Endpoint for internet access (like client)
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_db.id
  ]
  
  tags = {
    Name = "s3-gateway-endpoint"
  }
}

# AWS Backup resources moved to backup.tf



# Private Hosted Zone for example.com
resource "aws_route53_zone" "private" {
  name = "example.com"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = "example.com private zone"
  }
}

# DNS Records pointing to ALB
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "api"
  type    = "A"

  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "portal" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "portal"
  type    = "A"

  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "public" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "public"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.web_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.web_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
