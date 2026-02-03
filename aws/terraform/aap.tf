# AAP Controller Instance
#
# Creates the AAP controller with Vault SSH CA trust pre-configured.
# Only created if var.create_aap = true.

# -----------------------------------------------------------------------------
# Key Pair
# -----------------------------------------------------------------------------

module "key_pair" {
  count   = var.create_aap ? 1 : 0
  source  = "terraform-aws-modules/key-pair/aws"
  version = "2.0.2"

  key_name           = "${var.name_prefix}-aap-key"
  create_private_key = true
}

# -----------------------------------------------------------------------------
# AAP Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "aap" {
  count = var.create_aap ? 1 : 0

  ami                         = local.aap_ami
  instance_type               = var.aap_instance_type
  key_name                    = module.key_pair[0].key_pair_name
  subnet_id                   = aws_subnet.public_az1.id
  vpc_security_group_ids      = [aws_security_group.aap[0].id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  # Configure Vault SSH CA trust via user_data
  user_data = <<-EOF
    #!/bin/bash
    set -e

    echo "Configuring Vault SSH CA trust..."

    # Create directory for CA keys
    mkdir -p /etc/ssh/vault-ca

    # Write Vault CA public key
    cat > /etc/ssh/vault-ca/trusted-user-ca-keys.pem <<'CAKEY'
    ${local.vault_ca_public_key}
    CAKEY

    chmod 644 /etc/ssh/vault-ca/trusted-user-ca-keys.pem

    # Configure sshd to trust Vault CA
    if ! grep -q "TrustedUserCAKeys" /etc/ssh/sshd_config; then
      echo "" >> /etc/ssh/sshd_config
      echo "# Vault SSH CA" >> /etc/ssh/sshd_config
      echo "TrustedUserCAKeys /etc/ssh/vault-ca/trusted-user-ca-keys.pem" >> /etc/ssh/sshd_config
    fi

    # Restart sshd
    systemctl restart sshd

    echo "Vault SSH CA trust configured."
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-aap"
    Role = "aap-controller"
  })

  depends_on = [data.http.vault_ca_public_key]
}

# -----------------------------------------------------------------------------
# ALB and HTTPS (optional)
# -----------------------------------------------------------------------------

# ACME registration for Let's Encrypt
resource "tls_private_key" "acme" {
  count     = var.create_aap && var.create_alb ? 1 : 0
  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  count           = var.create_aap && var.create_alb ? 1 : 0
  account_key_pem = tls_private_key.acme[0].private_key_pem
  email_address   = local.email_address
}

resource "acme_certificate" "cert" {
  count                     = var.create_aap && var.create_alb ? 1 : 0
  account_key_pem           = acme_registration.reg[0].account_key_pem
  common_name               = local.aap_fqdn
  subject_alternative_names = [local.aap_fqdn]

  dns_challenge {
    provider = "route53"
    config = {
      AWS_DEFAULT_REGION = var.aws_region
    }
  }
}

resource "aws_acm_certificate" "cert" {
  count             = var.create_aap && var.create_alb ? 1 : 0
  private_key       = acme_certificate.cert[0].private_key_pem
  certificate_body  = acme_certificate.cert[0].certificate_pem
  certificate_chain = acme_certificate.cert[0].issuer_pem

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-aap-cert"
  })
}

# ALB
resource "aws_lb" "aap" {
  count = var.create_aap && var.create_alb ? 1 : 0

  name               = "${var.name_prefix}-aap-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = [aws_subnet.public_az1.id, aws_subnet.public_az2.id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-aap-alb"
  })
}

resource "aws_lb_target_group" "aap" {
  count = var.create_aap && var.create_alb ? 1 : 0

  name     = "${var.name_prefix}-aap-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = "443"
    protocol            = "HTTPS"
    interval            = 180
    timeout             = 60
    healthy_threshold   = 2
    unhealthy_threshold = 10
    matcher             = "200-499"
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-aap-tg"
  })
}

resource "aws_lb_listener" "https" {
  count = var.create_aap && var.create_alb ? 1 : 0

  load_balancer_arn = aws_lb.aap[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aap[0].arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = var.create_aap && var.create_alb ? 1 : 0

  load_balancer_arn = aws_lb.aap[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group_attachment" "aap" {
  count = var.create_aap && var.create_alb ? 1 : 0

  target_group_arn = aws_lb_target_group.aap[0].arn
  target_id        = aws_instance.aap[0].id
  port             = 443
}

# Route53 record
resource "aws_route53_record" "aap" {
  count = var.create_aap && var.create_alb ? 1 : 0

  zone_id = data.aws_route53_zone.hashidemos[0].zone_id
  name    = local.aap_fqdn
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.aap[0].dns_name]
}

# Wait for AAP to be healthy
resource "terraform_data" "wait_for_aap" {
  count = var.create_aap && var.create_alb ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for AAP to become healthy..."
      for i in {1..60}; do
        status=$(aws --region ${var.aws_region} elbv2 describe-target-health \
          --target-group-arn ${aws_lb_target_group.aap[0].arn} \
          --query 'TargetHealthDescriptions[0].TargetHealth.State' \
          --output text 2>/dev/null || echo "unknown")

        echo "Health status: $status"

        if [ "$status" = "healthy" ]; then
          echo "AAP is healthy!"
          sleep 30
          exit 0
        fi

        sleep 10
      done

      echo "Timeout waiting for AAP (may still be starting up)"
      exit 0
    EOT
  }

  depends_on = [
    aws_instance.aap,
    aws_lb_target_group_attachment.aap,
    aws_route53_record.aap
  ]

  triggers_replace = {
    instance_id = aws_instance.aap[0].id
  }
}

# -----------------------------------------------------------------------------
# Locals for AAP URL
# -----------------------------------------------------------------------------

locals {
  # This is the actual AAP URL (computed after resources are created)
  # Used for outputs, not for provider configuration
  aap_url = var.create_aap ? (
    var.create_alb ? "https://${local.aap_fqdn}" : "https://${aws_instance.aap[0].public_ip}"
  ) : var.aap_host
}
