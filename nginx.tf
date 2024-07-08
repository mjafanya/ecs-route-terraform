resource "aws_security_group" "sgfornginx" {
  vpc_id      = aws_vpc.Ecsvpcstrapi.id
  description = "This is for strapy application"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {

    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Sg-for-nginx-rm"
  }
  depends_on = [ aws_ecs_service.ecs_service_strapi ]

}
resource "tls_private_key" "fornginx" {
  algorithm  = "RSA"
  rsa_bits   = 4096
  depends_on = [aws_security_group.sgfornginx]

  lifecycle {
    ignore_changes = [private_key_pem, public_key_openssh]
  }
}
resource "aws_key_pair" "keypairfornginx" {
  key_name   = "keyforstrapi"
  public_key = tls_private_key.fornginx.public_key_openssh
  depends_on = [ tls_private_key.fornginx ]
  lifecycle {
    ignore_changes = [public_key]
  }
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

  owners = ["099720109477"]
  depends_on = [ aws_key_pair.keypairfornginx ]
}


resource "aws_instance" "ec2fornginx" {
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = "us-east-2a"
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.sgfornginx.id]
  subnet_id                   = aws_subnet.publicsubnets[0].id
  key_name                    = aws_key_pair.keypairfornginx.key_name
  associate_public_ip_address = true
  ebs_block_device {
    device_name           = "/dev/sdh"
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }
  tags = {
    Name = "ec2fornginx-rm"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    sudo apt-get update
    sudo apt-get install -y nginx

    # Configure Nginx site
    sudo tee /etc/nginx/sites-available/strapi > /dev/null <<'EOT'
    server {
        listen 80;
        server_name jafanya.contentecho.in;

        location / {
            proxy_pass http://${data.aws_network_interface.interface_tags.association[0].public_ip}:1337;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
    EOT

    # Enable and configure the site
    sudo ln -s /etc/nginx/sites-available/strapi /etc/nginx/sites-enabled/
    sudo rm /etc/nginx/sites-enabled/default

    # Restart Nginx to apply changes
    sudo systemctl restart nginx
  EOF
  depends_on = [
    data.aws_ami.ubuntu
  ]
}

