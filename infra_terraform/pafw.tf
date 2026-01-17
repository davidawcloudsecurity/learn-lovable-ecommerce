data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

resource "aws_iam_role" "pafw_role" {
  name = "pafw-role"
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

resource "aws_iam_role_policy_attachment" "pafw_ssm" {
  role       = aws_iam_role.pafw_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "pafw_profile" {
  name = "pafw-profile"
  role = aws_iam_role.pafw_role.name
}

resource "aws_security_group" "pafw_sg" {
  name_prefix = "pafw-sg-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "pafw" {
  ami                    = "ami-08b9e92fdf5f5641c"
  instance_type          = "m5.2xlarge"
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.pafw_sg.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.pafw_profile.name
  }
  
  user_data = base64encode(<<-EOF
    <powershell>
    net user ec2-user P@ssw0rd123 /add
    net localgroup administrators ec2-user /add
    </powershell>
  EOF
  )

  tags = {
    Name = "pafw"
  }
}

output "pafw_instance_id" {
  value = aws_instance.pafw.id
}

output "pafw_public_ip" {
  value = aws_instance.pafw.public_ip
}
