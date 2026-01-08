variable "region" {
  description = "AWS region"
  default     = "us-east-1"
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

variable "create_new_role" {
  type        = bool
  default     = true
  description = "Whether to create new role or use existing"
}

provider "aws" {
  region  = var.region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "100.115.58.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "public_facing_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "100.115.58.0/28"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1a"
  }
}

resource "aws_subnet" "public_facing_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "100.115.58.16/28"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet_1b"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "100.115.58.32/28"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false # temp for ssm

  tags = {
    Name = "private-app-subnet"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "100.115.58.48/28"
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
  domain     = "vpc"
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
  cidr_block              = "100.115.58.64/28"
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
    description = "HTTP from public subnet"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
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
  name = "ec2_ssm_role"

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

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_ssm_role.name
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2_ssm_profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Generate private key
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create self-signed certificate
resource "tls_self_signed_cert" "example" {
  private_key_pem = tls_private_key.example.private_key_pem

  subject {
    common_name  = "api.ecommerce.local"
    organization = "Ecommerce Inc"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [
    "api.ecommerce.local",
    "*.ecommerce.local"
  ]
}

# Import self-signed certificate into ACM
resource "aws_acm_certificate" "imported" {
  private_key      = tls_private_key.example.private_key_pem
  certificate_body = tls_self_signed_cert.example.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "self-signed-cert"
  }
}
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create self-signed certificate
resource "tls_self_signed_cert" "example" {
  private_key_pem = tls_private_key.example.private_key_pem

  subject {
    common_name  = "api.ecommerce.local"
    organization = "Ecommerce Inc"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [
    "api.ecommerce.local",
    "*.ecommerce.local"
  ]
}

# Import self-signed certificate into ACM
resource "aws_acm_certificate" "imported" {
  private_key      = tls_private_key.example.private_key_pem
  certificate_body = tls_self_signed_cert.example.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "self-signed-cert"
  }
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

# Target Groups for ECS (IP-based)
resource "aws_lb_target_group" "frontend" {
  name        = "frontend-tgv2"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_lb_target_group" "backend" {
  name        = "backend-tgv2"
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
    matcher             = "200-399"
  }
}

# Random Target Groups for HTTPS
resource "aws_lb_target_group" "auth_service" {
  name        = "auth-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/auth/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "user_service" {
  name        = "user-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/users/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "product_service" {
  name        = "product-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/products/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "order_service" {
  name        = "order-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/orders/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "payment_service" {
  name        = "payment-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/payments/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "inventory_service" {
  name        = "inventory-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/inventory/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "notification_service" {
  name        = "notification-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/notifications/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "analytics_service" {
  name        = "analytics-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/analytics/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "search_service" {
  name        = "search-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/search/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "cart_service" {
  name        = "cart-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/cart/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "review_service" {
  name        = "review-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/reviews/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

resource "aws_lb_target_group" "admin_service" {
  name        = "admin-service-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    path                = "/admin/health"
    protocol            = "HTTPS"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 5
    matcher             = "200"
  }
}

# Target Groups for ASG (Instance-based)
resource "aws_lb_target_group" "frontend_asg" {
  name        = "frontend-tgv1"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
}

resource "aws_lb_target_group" "backend_asg" {
  name        = "backend-tgv1"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.imported.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
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

# HTTPS Listener Rules
resource "aws_lb_listener_rule" "auth_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth_service.arn
  }

  condition {
    path_pattern {
      values = ["/auth/*"]
    }
  }
}

resource "aws_lb_listener_rule" "user_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_service.arn
  }

  condition {
    path_pattern {
      values = ["/users/*"]
    }
  }
}

resource "aws_lb_listener_rule" "product_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.product_service.arn
  }

  condition {
    path_pattern {
      values = ["/products/*"]
    }
  }
}

resource "aws_lb_listener_rule" "order_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.order_service.arn
  }

  condition {
    path_pattern {
      values = ["/orders/*"]
    }
  }
}

resource "aws_lb_listener_rule" "payment_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payment_service.arn
  }

  condition {
    path_pattern {
      values = ["/payments/*"]
    }
  }
}

resource "aws_lb_listener_rule" "inventory_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 6

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inventory_service.arn
  }

  condition {
    path_pattern {
      values = ["/inventory/*"]
    }
  }
}

resource "aws_lb_listener_rule" "notification_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 7

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.notification_service.arn
  }

  condition {
    path_pattern {
      values = ["/notifications/*"]
    }
  }
}

resource "aws_lb_listener_rule" "analytics_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 8

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.analytics_service.arn
  }

  condition {
    path_pattern {
      values = ["/analytics/*"]
    }
  }
}

resource "aws_lb_listener_rule" "search_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 9

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.search_service.arn
  }

  condition {
    path_pattern {
      values = ["/search/*"]
    }
  }
}

resource "aws_lb_listener_rule" "cart_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cart_service.arn
  }

  condition {
    path_pattern {
      values = ["/cart/*"]
    }
  }
}

resource "aws_lb_listener_rule" "review_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 11

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.review_service.arn
  }

  condition {
    path_pattern {
      values = ["/reviews/*"]
    }
  }
}

resource "aws_lb_listener_rule" "admin_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 12

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin_service.arn
  }

  condition {
    path_pattern {
      values = ["/admin/*"]
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
    cd /opt
    git clone -b SR-965 https://github.com/davidawcloudsecurity/learn-lovable-ecommerce.git app
    cd app
    echo "VITE_S3_BUCKET_URL=https://${aws_s3_bucket.product_images.bucket}.s3.${data.aws_region.current.id}.amazonaws.com" > .env
    npm i;npm run build
    
    # Install and configure nginx
    apt install -y nginx
    
    # Configure nginx to serve React app
    cat > /etc/nginx/sites-available/default <<'NGINX'
    server {
      listen 80;
      root /opt/app/dist;
      index index.html;
           
      # Serve React app
      location / {
        try_files $uri $uri/ /index.html;
      }
    }
    NGINX
    
    systemctl restart nginx
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
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install -y unzip
unzip awscliv2.zip
./aws/install
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

# Get credentials from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value --secret-id postgres-credentials --region ${var.region} --query SecretString --output text)
POSTGRES_PASSWORD=$(echo $SECRET | jq -r '.password')

# Create .env file
echo "POSTGRES_HOST=$RDS_ENDPOINT" > .env
echo "POSTGRES_DB=wordpress" >> .env
echo "POSTGRES_USER=wordpress" >> .env
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env

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
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -p 5432:5432 \
  postgres:16

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
  if docker exec postgres bash -c "PGPASSWORD=$POSTGRES_PASSWORD pg_isready -h $RDS_ENDPOINT -U wordpress -d wordpress" > /dev/null 2>&1; then
	echo "✅ PostgreSQL is ready!"
	break
  else
	echo "⏳ Attempt $i/30: PostgreSQL not ready yet..."
	sleep 5
  fi
done

# Create products table
docker exec postgres bash -c "PGPASSWORD=$POSTGRES_PASSWORD psql -h $RDS_ENDPOINT -U wordpress -d wordpress -c \"CREATE TABLE IF NOT EXISTS products (
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
    category VARCHAR(100),
    UNIQUE(name, country)
);\""

# Insert sample data if 100.MD exists
if [ -f "./100.MD" ]; then
  cat ./100.MD | docker exec -i postgres bash -c "PGPASSWORD=$POSTGRES_PASSWORD psql -h $RDS_ENDPOINT -U wordpress -d wordpress"
fi

# Start the Node.js application
nohup node server.js > /var/log/node-app.log 2>&1 &
	EOF
)
}
# WORDPRESS AUTOSCALING GROUP
resource "aws_autoscaling_group" "wordpress" {
  name                = "wordpress-asg"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.private_app.id]
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.frontend_asg.arn]

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "auto-delete"
    value               = "no"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

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
  password			   = local.postgres_password
  db_subnet_group_name = aws_db_subnet_group.postgres_subnet_group.name
  vpc_security_group_ids = [aws_security_group.private_db.id]
  skip_final_snapshot  = true
  publicly_accessible  = false

  tags = {
    Name = "postgres-instance"
    auto-delete = "no"
  }
}

# MYSQL AUTOSCALING GROUP
resource "aws_autoscaling_group" "mysql" {
  name                = "mysql-asg"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1  # Changed to 2 for HA
  vpc_zone_identifier = [
    aws_subnet.private_db.id,
    aws_subnet.private_db_1b.id  # Add second subnet
  ]
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.backend_asg.arn]

  launch_template {
    id      = aws_launch_template.mysql.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "mysql-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "auto-delete"
    value               = "no"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

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

# Bucket policy disabled due to BlockPublicPolicy setting
/*
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
*/

# Null resource to download and upload images from GitHub repo to S3
resource "null_resource" "upload_images_to_s3" {

  depends_on = [
    aws_s3_bucket.product_images
    # aws_s3_bucket_policy.public_read_policy  # Commented out - policy disabled
  ]

  provisioner "local-exec" {
    command = <<-EOT
      pwd
      # Check if the images directory exists
      if [ -d "../public/assets/images" ]; then
        # Upload all files from public/assets/images to S3
        aws s3 cp ../public/assets/images/ s3://${aws_s3_bucket.product_images.bucket}/assets/images/ --recursive
        echo "Images uploaded successfully to S3 bucket: ${aws_s3_bucket.product_images.bucket}"
      else
        echo "Images directory not found in the repository"
      fi
      sudo yum update -y
      curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
      sudo yum install -y nodejs
      cd /home
      sudo git clone https://github.com/davidawcloudsecurity/learn-lovable-borderless-trade-sphere.git
      cd learn-lovable-borderless-trade-sphere/
      sudo npm i;sudo npm run build;
      aws s3 cp dist s3://${aws_s3_bucket.product_images.bucket} --recursive
      cd /home
      sudo rm -rf learn-lovable-borderless-trade-sphere
    EOT
  }
  # Trigger re-execution if bucket changes
  triggers = {
    bucket_name = aws_s3_bucket.product_images.bucket
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

resource "aws_cloudfront_distribution" "web_distribution" {
  origin {
    domain_name = aws_lb.example.dns_name
    origin_id   = "ALB-${aws_lb.example.name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
      origin_keepalive_timeout = 5
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
  comment             = "CloudFront distribution for ALB"

  aliases = []

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ALB-${aws_lb.example.name}"
    
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    
    viewer_protocol_policy = "allow-all"
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern     = "/assets/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.product_images.bucket}"
    
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
    
    viewer_protocol_policy = "allow-all"
    compress               = true
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_lb.example,
    aws_s3_bucket.product_images
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
                  listen 8080;
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
              curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
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

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "ecommerce-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "ecommerce-cluster"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# ECS Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public_facing.id]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.public_facing.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-tasks-sg"
  }
}

# ECS Task Definition 1 - Frontend Nginx
resource "aws_ecs_task_definition" "frontend_nginx" {
  family                   = "frontend-nginx"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "nginx-frontend"
      image = "nginx:alpine"
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/frontend-nginx"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        {
          name  = "NGINX_HOST"
          value = "localhost"
        },
        {
          name  = "NGINX_PORT"
          value = "80"
        }
      ]
    }
  ])

  tags = {
    Name = "frontend-nginx-task"
  }
}

# ECS Task Definition 2 - Backend Nginx
resource "aws_ecs_task_definition" "backend_nginx" {
  family                   = "backend-nginx"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "nginx-backend"
      image = "nginx:alpine"
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/backend-nginx"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        {
          name  = "NGINX_HOST"
          value = "0.0.0.0"
        },
        {
          name  = "NGINX_PORT"
          value = "80"
        }
      ]
    }
  ])

  tags = {
    Name = "backend-nginx-task"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "frontend_nginx" {
  name              = "/ecs/frontend-nginx"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "backend_nginx" {
  name              = "/ecs/backend-nginx"
  retention_in_days = 7
}

# ECS Service 1 - Frontend
resource "aws_ecs_service" "frontend" {
  name            = "frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend_nginx.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_app.id]
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "nginx-frontend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.example]

  tags = {
    Name = "frontend-ecs-service"
  }
}

# ECS Service 2 - Backend
resource "aws_ecs_service" "backend" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend_nginx.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_app.id]
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "nginx-backend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener_rule.api_rule]

  tags = {
    Name = "backend-ecs-service"
  }
}

# Outputs
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.web_distribution.domain_name
}

output "s3_assets_url" {
  value = "https://${aws_cloudfront_distribution.web_distribution.domain_name}/assets/"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_services" {
  value = {
    frontend = aws_ecs_service.frontend.name
    backend  = aws_ecs_service.backend.name
  }
}
