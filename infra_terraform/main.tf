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
  default     = false
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
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "public_facing_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1a"
  }
}

resource "aws_subnet" "public_facing_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1b"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false # temp for ssm

  tags = {
    Name = "private-app-subnet"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false # temp for ssm

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
  cidr_block              = "10.0.7.0/24"
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
    description = "Setup to allow SSM"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
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
    aws_s3_bucket.product_images,
    aws_s3_bucket_policy.public_read_policy
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

resource "aws_db_subnet_group" "postgres_subnet_group" {
  name       = "postgres-subnet-group"
  subnet_ids = [
	aws_subnet.private_db_1b.id,
	aws_subnet.private_db.id
	]

  tags = {
    Name = "postgres-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  db_name              = "wordpress"
  username             = "wordpress"
  password             = "rootpassword"
  db_subnet_group_name = aws_db_subnet_group.postgres_subnet_group.name
  vpc_security_group_ids = [aws_security_group.private_db.id]
  skip_final_snapshot  = true
  publicly_accessible  = false

  tags = {
    Name = "postgres-instance"
  }
}
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

# Revised public access block: Block ACLs but allow public policies
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.product_images.id

  block_public_acls       = true   # Block public ACLs
  block_public_policy     = false  # ✅ Allow public bucket policies
  ignore_public_acls      = true   # Ignore public ACLs
  restrict_public_buckets = false  # ✅ Allow public policies
}

# Bucket policy remains unchanged (uses policy, not ACLs)
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.product_images.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.product_images.arn}/*"
      }
    ]
  })
  depends_on = [
    aws_s3_bucket.product_images,
    aws_s3_bucket_public_access_block.public_access  # This ensures PAB is applied first
  ]
}

# Null resource to download and upload images from GitHub repo to S3
resource "null_resource" "upload_images_to_s3" {

  depends_on = [
    aws_s3_bucket.product_images,
    aws_s3_bucket_policy.public_read_policy
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

# Cache Policies (predefined by AWS - best to use these)
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "no_cache" {
  name = "Managed-CachingDisabled"
}

# Origin Request Policies
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_origin_request_policy" "cors_s3" {
  name = "Managed-CORS-S3Origin"
}

# CloudFront Origin Access Identity for S3
resource "aws_cloudfront_origin_access_identity" "s3_oai" {
  comment = "OAI for ${aws_s3_bucket.product_images.bucket}"
}

# Update S3 bucket policy to allow CloudFront access
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

# CloudFront Distribution with both ALB and S3 origins
resource "aws_cloudfront_distribution" "web_distribution" {
  origin {
    domain_name = "${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "APIGateway-${aws_api_gateway_rest_api.api.name}"
	origin_path = "/${aws_api_gateway_stage.prod.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = aws_s3_bucket.product_images.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.product_images.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_oai.cloudfront_access_identity_path
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
  # API routes to API Gateway
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "APIGateway-${aws_api_gateway_rest_api.api.name}"
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"  # AllViewerExceptHostHeader
    viewer_protocol_policy = "allow-all"
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
    aws_api_gateway_rest_api.api,
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

# Outputs
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.web_distribution.domain_name
}

output "s3_assets_url" {
  value = "https://${aws_cloudfront_distribution.web_distribution.domain_name}/assets/"
}
