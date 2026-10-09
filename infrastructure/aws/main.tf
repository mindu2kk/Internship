data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023_x86_64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name_prefix      = "${var.project}-${var.environment}"
  parameter_prefix = "/${var.project}/${var.environment}"
  cloudflare_tunnel_parameter_name = coalesce(
    var.cloudflare_tunnel_parameter_name,
    "${local.parameter_prefix}/cloudflare_tunnel_token",
  )
  release_parameter_name           = "${local.parameter_prefix}/release_backend_image"
  proxy_release_parameter_name     = "${local.parameter_prefix}/release_proxy_image"
  frontend_url_parameter_name      = "${local.parameter_prefix}/frontend_url"
  cloudflared_image_parameter_name = "${local.parameter_prefix}/cloudflared_image"
  log_group_name                   = "/${var.project}/${var.environment}/app"
  backup_bucket_name               = "${var.project}-${data.aws_caller_identity.current.account_id}-${var.environment}-backup"
  github_oidc_provider_arn = coalesce(
    var.github_oidc_provider_arn,
    try(aws_iam_openid_connect_provider.github[0].arn, null),
  )
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  runtime_secret_parameter_paths = {
    for environment_name, leaf_name in var.runtime_secret_parameter_names :
    environment_name => "${local.parameter_prefix}/${leaf_name}"
  }
}

resource "aws_vpc" "this" {
  cidr_block                       = "10.42.0.0/24"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "origin" {
  vpc_id                          = aws_vpc.this.id
  cidr_block                      = "10.42.0.0/26"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, 0)
  availability_zone               = "${var.aws_region}a"
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = false

  tags = {
    Name = "${local.name_prefix}-origin-ipv6"
  }
}

resource "aws_route_table" "origin" {
  vpc_id = aws_vpc.this.id

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-origin-ipv6"
  }
}

resource "aws_route_table_association" "origin" {
  subnet_id      = aws_subnet.origin.id
  route_table_id = aws_route_table.origin.id
}

resource "aws_security_group" "origin" {
  name        = "${local.name_prefix}-origin"
  description = "No ingress. Origin only makes outbound IPv6 tunnel and AWS service connections."
  vpc_id      = aws_vpc.this.id

  egress {
    description      = "HTTPS to Cloudflare and AWS dual-stack services"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Cloudflare Tunnel QUIC"
    from_port        = 7844
    to_port          = 7844
    protocol         = "udp"
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Cloudflare Tunnel TCP fallback"
    from_port        = 7844
    to_port          = 7844
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.name_prefix}-origin"
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "proxy" {
  name                 = "${local.name_prefix}-proxy"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the newest ten immutable backend images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["sha-"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "proxy" {
  repository = aws_ecr_repository.proxy.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the newest ten immutable API proxy images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["sha-"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_s3_bucket" "backup" {
  bucket = local.backup_bucket_name
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-daily-backups"
    status = "Enabled"

    filter {
      prefix = "daily/"
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = 30
}

resource "aws_ssm_parameter" "backend_release" {
  name  = local.release_parameter_name
  type  = "String"
  value = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "proxy_release" {
  name  = local.proxy_release_parameter_name
  type  = "String"
  value = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "frontend_url" {
  name  = local.frontend_url_parameter_name
  type  = "String"
  value = "https://www.invalid"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "cloudflared_image" {
  name  = local.cloudflared_image_parameter_name
  type  = "String"
  value = "pending"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_instance" "origin" {
  ami                         = data.aws_ssm_parameter.al2023_x86_64.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.origin.id
  associate_public_ip_address = false
  ipv6_address_count          = 1
  vpc_security_group_ids      = [aws_security_group.origin.id]
  iam_instance_profile        = aws_iam_instance_profile.origin.name
  user_data_replace_on_change = true

  depends_on = [aws_iam_role_policy.origin_runtime]

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size_gib
    tags = {
      Name = "${local.name_prefix}-origin-root"
    }
  }

  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    http_protocol_ipv6     = "enabled"
    instance_metadata_tags = "disabled"
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region                       = var.aws_region
    project                          = var.project
    environment                      = var.environment
    account_id                       = data.aws_caller_identity.current.account_id
    backup_bucket                    = aws_s3_bucket.backup.bucket
    backend_release_parameter_name   = aws_ssm_parameter.backend_release.name
    proxy_release_parameter_name     = aws_ssm_parameter.proxy_release.name
    frontend_url_parameter_name      = aws_ssm_parameter.frontend_url.name
    cloudflared_image_parameter_name = aws_ssm_parameter.cloudflared_image.name
    cloudflare_tunnel_parameter_name = local.cloudflare_tunnel_parameter_name
    log_group_name                   = aws_cloudwatch_log_group.app.name
    compose_file_b64                 = base64encode(file("${path.module}/../../SourceCode/deploy/aws/docker-compose.aws.yml"))
    refresh_file_b64                 = base64encode(file("${path.module}/../../SourceCode/deploy/aws/refresh.sh"))
    backup_file_b64                  = base64encode(file("${path.module}/../../SourceCode/deploy/aws/backup.sh"))
    runtime_secret_parameters        = join("\n", [for environment_name, parameter_path in local.runtime_secret_parameter_paths : "${environment_name}=${parameter_path}"])
  })

  lifecycle {
    precondition {
      condition     = trimspace(nonsensitive(var.budget_alert_email)) != ""
      error_message = "budget_alert_email is required; alerts must exist before creating billable resources."
    }
  }

  tags = {
    Name = "${local.name_prefix}-origin"
    Role = "aura-origin"
  }
}

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-monthly-cap"
  budget_type  = "COST"
  limit_amount = "28"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
