data "aws_availability_zones" "available" {
  state = "available"
}

# ALBs must span at least two Availability Zones. These subnets are public only
# for the AWS-managed load balancer; the EC2 application origin remains private.
resource "aws_subnet" "alb" {
  count = 2

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = cidrsubnet("10.42.0.0/24", 3, count.index + 2)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index + 1)
  availability_zone               = data.aws_availability_zones.available.names[count.index]
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = false

  tags = {
    Name = "${local.name_prefix}-alb-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "public-load-balancer"
  }
}

resource "aws_route_table" "alb" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-alb-public"
  }
}

resource "aws_route_table_association" "alb" {
  count = length(aws_subnet.alb)

  subnet_id      = aws_subnet.alb[count.index].id
  route_table_id = aws_route_table.alb.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Public HTTPS entry point for the AURA API."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from IPv4 clients"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTPS from IPv6 clients"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description     = "HTTP to the private API proxy only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.origin.id]
  }

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "origin_from_alb" {
  description                  = "Allow API traffic from the AURA ALB only"
  security_group_id            = aws_security_group.origin.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_lb" "api" {
  name                       = "${local.name_prefix}-api"
  internal                   = false
  load_balancer_type         = "application"
  ip_address_type            = "dualstack"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.alb[*].id
  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

resource "aws_lb_target_group" "api" {
  name                 = "${local.name_prefix}-api"
  port                 = 8080
  protocol             = "HTTP"
  protocol_version     = "HTTP1"
  target_type          = "instance"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    matcher             = "200"
    path                = "/healthz"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

resource "aws_lb_target_group_attachment" "origin" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.origin.id
  port             = 8080
}

resource "aws_acm_certificate" "api" {
  domain_name       = var.api_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# Set enable_https_listener=true only after the output CNAME has been created
# in ZoneDNS and ACM reports the certificate as issued.
resource "aws_acm_certificate_validation" "api" {
  count = var.enable_https_listener ? 1 : 0

  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for option in aws_acm_certificate.api.domain_validation_options : option.resource_record_name]
}

resource "aws_lb_listener" "https" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.api[0].certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "api_host" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    host_header {
      values = [var.api_domain_name]
    }
  }
}
