terraform {
  required_version = ">= 1.1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.23.0"
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
  cidr_block           = "10.0.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "public_facing_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.64/28"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1a"
  }
}

resource "aws_subnet" "public_facing_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.80/28"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1b"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.32/28"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-app-subnet"
  }
}

resource "aws_subnet" "private_app_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.48/28"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-app-subnet-1b"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.96/27"
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
  cidr_block              = "10.0.0.128/27"
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

resource "aws_lb_target_group" "frontend" {
  name     = "frontend-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "backend" {
  name     = "backend-tg"
  port     = 3001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/api/search"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api_rule" {
  listener_arn = aws_lb_listener.example.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api*"]
    }
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
RDS_ENDPOINT="${aws_db_instance.postgres.endpoint}"
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
  bucket = "learn-lovable-product-images-${random_id.suffix.hex}" # Use unique suffix to avoid bucket name conflicts

# ✅ This will automatically delete all objects when destroying the bucket
  force_destroy = true

  tags = {
    Name        = "Product Images"
    Environment = "production"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# Revised public access block: Block all public access
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.product_images.id

  block_public_acls       = true   # Block public ACLs
  block_public_policy     = true   # Block public bucket policies
  ignore_public_acls      = true   # Ignore public ACLs
  restrict_public_buckets = true   # Block public policies
}

# Bucket policy remains unchanged (uses policy, not ACLs)
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

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "alb_waf" {
  resource_arn = aws_lb.example.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_waf.arn
}

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

# ALB2
resource "aws_lb" "example2" {
  name               = "example-alb2"
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

resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    enabled             = true
    path                = "/"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

# Target Groups for 11 services
resource "aws_lb_target_group" "sp" {
  name        = "tg-sp"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/auth/health"
  }
}

resource "aws_lb_target_group" "tk" {
  name        = "tg-tk"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/tkt/health"
  }
}

resource "aws_lb_target_group" "sc" {
  name        = "tg-sc"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/sched/health"
  }
}

resource "aws_lb_target_group" "qr" {
  name        = "tg-qr"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/qr/health"
  }
}

resource "aws_lb_target_group" "kb" {
  name        = "tg-kb"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/kb/health"
  }
}

resource "aws_lb_target_group" "fc" {
  name        = "tg-fc"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/fac/health"
  }
}

resource "aws_lb_target_group" "bp" {
  name        = "tg-bp"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/proc/health"
  }
}

resource "aws_lb_target_group" "bm" {
  name        = "tg-bm"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/mgmt/health"
  }
}

resource "aws_lb_target_group" "bc" {
  name        = "tg-bc"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/cast/health"
  }
}

resource "aws_lb_target_group" "ap" {
  name        = "tg-ap"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_target_group" "ct" {
  name        = "tg-ct"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path = "/ct/health"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = trimspace(data.local_file.cert_arn.content)
  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = "200"
      content_type = "text/plain"
    }
  }
}

# Listener Rules
resource "aws_lb_listener_rule" "sp" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sp.arn
  }
  condition {
    path_pattern {
      values = ["/auth/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "tk" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 11
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tk.arn
  }
  condition {
    path_pattern {
      values = ["/tkt/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "sc" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 12
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sc.arn
  }
  condition {
    path_pattern {
      values = ["/sched/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "qr" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 13
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.qr.arn
  }
  condition {
    path_pattern {
      values = ["/qr/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "kb" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 15
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kb.arn
  }
  condition {
    path_pattern {
      values = ["/kb/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "fc" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 16
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fc.arn
  }
  condition {
    path_pattern {
      values = ["/fac/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "bp" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 18
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bp.arn
  }
  condition {
    path_pattern {
      values = ["/proc/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "bm" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 19
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bm.arn
  }
  condition {
    path_pattern {
      values = ["/mgmt/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "bc" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bc.arn
  }
  condition {
    path_pattern {
      values = ["/cast/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "redirect" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 21
  action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      host        = "api.example.com"
      path        = "/proc/#{path}"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }
  condition {
    path_pattern {
      values = ["/link/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "ap" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 22
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ap.arn
  }
  condition {
    host_header {
      values = ["portal.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "ct" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 23
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ct.arn
  }
  condition {
    path_pattern {
      values = ["/ct/*"]
    }
  }
  condition {
    host_header {
      values = ["api.example.com"]
    }
  }
}

# CloudFront Origin Access Identity for S3
resource "aws_cloudfront_origin_access_identity" "s3_oai" {
  comment = "OAI for ${aws_s3_bucket.product_images.bucket}"
}



# CloudFront Distribution with both ALB and S3 origins
resource "aws_cloudfront_distribution" "web_distribution" {
  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.product_images.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = aws_lb.example.dns_name
    origin_id   = "ALB-${aws_lb.example.name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for web application and static assets"
  default_root_object = "index.html"

  aliases = [] # Add your custom domain here if you have one

  # Default behavior routes to S3
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.product_images.bucket}"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # Managed-CORS-S3Origin
/*
    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }
*/
    viewer_protocol_policy = "allow-all" # Changed to allow both HTTP and HTTPS
/*    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
*/
  }

/*
  # API routes to ALB
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-${aws_lb.example.name}"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # Managed-AllViewer

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }
    viewer_protocol_policy = "allow-all" # Changed to allow both HTTP and HTTPS
    min_ttl                = 0
    default_ttl            = 0 # No caching for API by default
    max_ttl                = 0

  }
*/
  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # Uncomment if using custom domain:
    # acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."
    # ssl_support_method = "sni-only"
  }

  depends_on = [
    aws_s3_bucket_policy.cloudfront_access
  ]
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
output "alb_dns_name" {
  value = aws_lb.example.dns_name
}

# DocumentDB Subnet Group
resource "aws_docdb_subnet_group" "documentdb_subnet_group" {
  name       = "docdb-sg"
  subnet_ids = [aws_subnet.private_db.id, aws_subnet.private_db_1b.id]
  description = "DocumentDB subnet group"

  tags = {
    Name = "docdb-sg"
  }
}

# DocumentDB Parameter Group
resource "aws_docdb_cluster_parameter_group" "documentdb_params" {
  family      = "docdb4.0"
  name        = "docdb-params"
  description = "DocumentDB parameter group"

  parameter {
    name  = "audit_logs"
    value = "enabled"
  }

  parameter {
    name  = "profiler"
    value = "enabled"
  }
}

# Secrets Manager for DocumentDB credentials
resource "aws_secretsmanager_secret" "documentdb_credentials" {
  name        = "docdb/creds2"
  description = "DocumentDB master user credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "documentdb_credentials" {
  secret_id = aws_secretsmanager_secret.documentdb_credentials.id
  secret_string = jsonencode({
    username = "appuser"
    password = random_password.documentdb_password.result
  })
}

resource "random_password" "documentdb_password" {
  length  = 16
  special = true
}

# DocumentDB Cluster
resource "aws_docdb_cluster" "documentdb_cluster" {
  cluster_identifier      = "docdb-cluster"
  engine                 = "docdb"
  engine_version         = "4.0.0"
  master_username        = "appuser"
  master_password        = random_password.documentdb_password.result
  backup_retention_period = 1
  preferred_backup_window = "16:00-16:30"
  preferred_maintenance_window = "sun:19:00-sun:19:30"
  skip_final_snapshot    = true
  deletion_protection    = false
  
  db_subnet_group_name   = aws_docdb_subnet_group.documentdb_subnet_group.name
  vpc_security_group_ids = [aws_security_group.private_db.id]
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.documentdb_params.name
  
  storage_encrypted = true
  kms_key_id       = aws_kms_key.documentdb_key.arn
  
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]

  tags = {
    Name = "docdb-cluster"
  }
}

# KMS Key for DocumentDB encryption
resource "aws_kms_key" "documentdb_key" {
  description             = "KMS key for DocumentDB encryption"
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "documentdb_key_alias" {
  name          = "alias/documentdb-key"
  target_key_id = aws_kms_key.documentdb_key.key_id
}

# DocumentDB Cluster Instances
resource "aws_docdb_cluster_instance" "documentdb_instance_1" {
  count              = 1
  identifier         = "docdb-instance-1"
  cluster_identifier = aws_docdb_cluster.documentdb_cluster.id
  instance_class     = "db.t4g.medium"
  availability_zone  = "${var.region}a"
  promotion_tier     = 0  # Primary writer

  tags = {
    Name = "docdb-instance-1"
  }
}

resource "aws_docdb_cluster_instance" "documentdb_instance_2" {
  count              = 1
  identifier         = "docdb-instance-2"
  cluster_identifier = aws_docdb_cluster.documentdb_cluster.id
  instance_class     = "db.t4g.medium"
  availability_zone  = "${var.region}b"
  promotion_tier     = 1  # Reader

  tags = {
    Name = "docdb-instance-2"
  }
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
    sp = aws_lb_target_group.sp.arn
    tk = aws_lb_target_group.tk.arn
    sc = aws_lb_target_group.sc.arn
    qr = aws_lb_target_group.qr.arn
    kb = aws_lb_target_group.kb.arn
    fc = aws_lb_target_group.fc.arn
    bp = aws_lb_target_group.bp.arn
    bm = aws_lb_target_group.bm.arn
    bc = aws_lb_target_group.bc.arn
    ap = aws_lb_target_group.ap.arn
    ct = aws_lb_target_group.ct.arn
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

# AWS Backup for DocumentDB
resource "aws_backup_vault" "docdb" {
  name        = "docdb-backup-vault"
  kms_key_arn = aws_kms_key.documentdb_key.arn
}

resource "aws_backup_plan" "docdb" {
  name = "docdb-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.docdb.name
    schedule          = "cron(0 2 * * ? *)"  # Daily at 2 AM

    lifecycle {
      cold_storage_after = 30
      delete_after       = 365
    }

    recovery_point_tags = {
      Environment = "production"
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "aws-backup-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "docdb" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "docdb-backup-selection"
  plan_id      = aws_backup_plan.docdb.id

  resources = [
    aws_docdb_cluster.documentdb_cluster.arn
  ]
}

# ElastiCache Redis Subnets
resource "aws_subnet" "private_redis_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.160/28"
  availability_zone = "${var.region}a"
  
  tags = {
    Name = "private-redis-subnet-1a"
  }
}

resource "aws_subnet" "private_redis_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.176/28"
  availability_zone = "${var.region}b"
  
  tags = {
    Name = "private-redis-subnet-1b"
  }
}

# Route table associations for Redis subnets
resource "aws_route_table_association" "private_redis_1a" {
  subnet_id      = aws_subnet.private_redis_1a.id
  route_table_id = aws_route_table.private_db.id
}

resource "aws_route_table_association" "private_redis_1b" {
  subnet_id      = aws_subnet.private_redis_1b.id
  route_table_id = aws_route_table.private_db.id
}

# ElastiCache Redis Cluster with Backup Configuration
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "redis-subnet-group"
  subnet_ids = [aws_subnet.private_redis_1a.id, aws_subnet.private_redis_1b.id]
  
  tags = {
    Name = "redis-subnet-group"
  }
}

resource "aws_elasticache_replication_group" "redis_cluster" {
  replication_group_id         = "dbs-elasticache-ecommerce-cluster"
  description                  = "Redis cluster for ecommerce application"
  
  # Configuration matching the case cluster
  node_type                    = "cache.t3.micro"
  port                        = 6379
  parameter_group_name        = "default.redis7"
  
  # Multi-AZ and HA configuration
  num_cache_clusters          = 2
  automatic_failover_enabled  = true
  multi_az_enabled           = true
  preferred_cache_cluster_azs = ["${var.region}a", "${var.region}b"]
  
  # Security configuration
  subnet_group_name          = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids         = [aws_security_group.private_db.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result
  
  # Backup configuration
  snapshot_retention_limit   = 1
  snapshot_window           = "16:00-17:00"
  final_snapshot_identifier = "dbs-elasticache-ecommerce-cluster-final-snapshot"
  
  # Maintenance
  maintenance_window        = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade = true
  
  tags = {
    Name = "dbs-elasticache-ecommerce-cluster"
    Environment = "production"
  }
}

resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

# Redis Outputs
output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis_cluster.primary_endpoint_address
}

output "redis_reader_endpoint" {
  value = aws_elasticache_replication_group.redis_cluster.reader_endpoint_address
}
 
