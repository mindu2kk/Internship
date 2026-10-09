resource "aws_sns_topic" "operational_alerts" {
  name = "${local.name_prefix}-operational-alerts"
}

resource "aws_sns_topic_subscription" "operational_email" {
  topic_arn = aws_sns_topic.operational_alerts.arn
  protocol  = "email"
  endpoint  = nonsensitive(var.budget_alert_email)
}

resource "aws_cloudwatch_metric_alarm" "origin_status_check" {
  alarm_name          = "${local.name_prefix}-origin-status-check-failed"
  alarm_description   = "The AURA origin failed an EC2 system or instance status check."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operational_alerts.arn]
  ok_actions          = [aws_sns_topic.operational_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.origin.id
  }
}

resource "aws_cloudwatch_metric_alarm" "origin_cpu_high" {
  alarm_name          = "${local.name_prefix}-origin-cpu-high"
  alarm_description   = "The AURA origin CPU average exceeded 80 percent for 15 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operational_alerts.arn]
  ok_actions          = [aws_sns_topic.operational_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.origin.id
  }
}

resource "aws_cloudwatch_metric_alarm" "origin_memory_high" {
  alarm_name          = "${local.name_prefix}-origin-memory-high"
  alarm_description   = "The AURA origin memory usage exceeded 85 percent for five minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "mem_used_percent"
  namespace           = "AURA/${var.environment}"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operational_alerts.arn]
  ok_actions          = [aws_sns_topic.operational_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.origin.id
  }
}

resource "aws_cloudwatch_metric_alarm" "origin_disk_high" {
  alarm_name          = "${local.name_prefix}-origin-disk-high"
  alarm_description   = "The AURA origin root-disk usage exceeded 80 percent for five minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "disk_used_percent"
  namespace           = "AURA/${var.environment}"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.operational_alerts.arn]
  ok_actions          = [aws_sns_topic.operational_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.origin.id
  }
}

resource "aws_cloudwatch_dashboard" "staging" {
  dashboard_name = "${local.name_prefix}-operations"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "AURA origin CPU and status"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.origin.id, { stat = "Average", period = 300 }],
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.origin.id, { stat = "Maximum", period = 300 }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "AURA origin memory and disk"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AURA/${var.environment}", "mem_used_percent", "InstanceId", aws_instance.origin.id, { stat = "Average", period = 60 }],
            ["AURA/${var.environment}", "disk_used_percent", "InstanceId", aws_instance.origin.id, { stat = "Average", period = 60 }],
          ]
        }
      },
    ]
  })
}
