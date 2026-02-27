# Frontend Stack
# Demonstrates: multiple units composition, values passing, cross-unit dependencies

# Stack configuration
stack {
  name        = "frontend"
  description = "Frontend infrastructure with S3, CloudFront, and Route53"
}

# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Local values for the stack
locals {
  # Load environment and common values
  env_values = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_values.locals.environment

  common_values = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  project       = local.common_values.locals.project
  region        = local.common_values.locals.region
  domain        = local.common_values.locals.domain

  # Stack-specific configuration
  frontend_domain = "${local.environment}.${local.domain}"

  # Certificate must be in us-east-1 for CloudFront
  certificate_region = "us-east-1"
}

# Unit 1: S3 bucket for static assets
unit "s3_bucket" {
  source = "../../units/s3"

  values = {
    bucket_name         = "${local.project}-${local.environment}-frontend"
    versioning_enabled  = true
    block_public_access = false  # CloudFront needs access

    # Website configuration
    website = {
      index_document = "index.html"
      error_document = "error.html"
    }

    # CORS for API calls
    cors_rules = [
      {
        allowed_headers = ["*"]
        allowed_methods = ["GET", "HEAD"]
        allowed_origins = ["https://${local.frontend_domain}"]
        expose_headers  = ["ETag"]
        max_age_seconds = 3000
      }
    ]

    # Lifecycle - archive old versions
    lifecycle_rules = [
      {
        id      = "cleanup-old-versions"
        enabled = true
        noncurrent_version_expiration = {
          days = 30
        }
      }
    ]

    tags = {
      Component = "static-assets"
    }
  }
}

# Unit 2: CloudFront distribution
unit "cloudfront" {
  source = "../../units/cloudfront"

  # Depends on S3 bucket
  dependencies = ["s3_bucket", "acm_certificate"]

  values = {
    # Origin configuration
    origin = {
      domain_name = unit.s3_bucket.outputs.bucket_regional_domain_name
      origin_id   = "S3-${unit.s3_bucket.outputs.bucket_id}"

      # Use OAI for S3 access
      s3_origin_config = {
        origin_access_identity = "origin-access-identity/cloudfront/EXAMPLE"
      }
    }

    # Cache behavior
    default_cache_behavior = {
      allowed_methods        = ["GET", "HEAD", "OPTIONS"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "S3-${unit.s3_bucket.outputs.bucket_id}"
      viewer_protocol_policy = "redirect-to-https"
      compress               = true

      forwarded_values = {
        query_string = false
        cookies = {
          forward = "none"
        }
      }

      min_ttl     = 0
      default_ttl = 3600
      max_ttl     = 86400
    }

    # Custom error responses for SPA
    custom_error_responses = [
      {
        error_code         = 403
        response_code      = 200
        response_page_path = "/index.html"
      },
      {
        error_code         = 404
        response_code      = 200
        response_page_path = "/index.html"
      }
    ]

    # SSL/TLS configuration
    viewer_certificate = {
      acm_certificate_arn      = unit.acm_certificate.outputs.certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }

    # Domain aliases
    aliases = [local.frontend_domain]

    # Geographic restrictions (optional)
    geo_restriction = {
      restriction_type = "none"
    }

    # Enable IPv6
    is_ipv6_enabled = true

    # Price class
    price_class = local.environment == "prod" ? "PriceClass_All" : "PriceClass_100"

    # Default root object
    default_root_object = "index.html"

    # Logging
    logging_config = {
      bucket          = "${local.project}-${local.environment}-logs.s3.amazonaws.com"
      prefix          = "cloudfront/${local.environment}/"
      include_cookies = false
    }

    tags = {
      Component = "cdn"
    }
  }
}

# Unit 3: ACM Certificate (in us-east-1 for CloudFront)
unit "acm_certificate" {
  source = "../../units/acm"

  values = {
    domain_name = local.frontend_domain

    subject_alternative_names = [
      "www.${local.frontend_domain}"
    ]

    validation_method = "DNS"

    # Force region to us-east-1 for CloudFront
    provider_region = local.certificate_region

    tags = {
      Component = "ssl-certificate"
    }
  }
}

# Unit 4: Route53 records
unit "route53_records" {
  source = "../../units/route53/records"

  # Depends on CloudFront and ACM
  dependencies = ["cloudfront", "acm_certificate"]

  values = {
    zone_name = local.domain

    records = [
      # Main domain - A record alias to CloudFront
      {
        name = local.frontend_domain
        type = "A"
        alias = {
          name                   = unit.cloudfront.outputs.distribution_domain_name
          zone_id                = unit.cloudfront.outputs.distribution_hosted_zone_id
          evaluate_target_health = false
        }
      },
      # AAAA record for IPv6
      {
        name = local.frontend_domain
        type = "AAAA"
        alias = {
          name                   = unit.cloudfront.outputs.distribution_domain_name
          zone_id                = unit.cloudfront.outputs.distribution_hosted_zone_id
          evaluate_target_health = false
        }
      },
      # ACM validation records
      {
        name    = unit.acm_certificate.outputs.validation_record_name
        type    = unit.acm_certificate.outputs.validation_record_type
        records = [unit.acm_certificate.outputs.validation_record_value]
        ttl     = 60
      }
    ]
  }
}

# Unit 5: CloudFront Origin Access Identity (OAI)
unit "cloudfront_oai" {
  source = "../../units/cloudfront-oai"

  values = {
    comment = "OAI for ${local.project} ${local.environment} frontend"
  }
}

# Unit 6: S3 bucket policy for CloudFront access
unit "s3_bucket_policy" {
  source = "../../units/s3-policy"

  # Depends on S3 bucket and CloudFront OAI
  dependencies = ["s3_bucket", "cloudfront_oai"]

  values = {
    bucket_id = unit.s3_bucket.outputs.bucket_id

    policy_statements = [
      {
        sid    = "CloudFrontAccess"
        effect = "Allow"
        principals = {
          type        = "AWS"
          identifiers = [unit.cloudfront_oai.outputs.iam_arn]
        }
        actions   = ["s3:GetObject"]
        resources = ["${unit.s3_bucket.outputs.bucket_arn}/*"]
      }
    ]
  }
}

# Unit 7: CloudWatch alarms for monitoring
unit "cloudwatch_alarms" {
  source = "../../units/cloudwatch-alarms"

  dependencies = ["cloudfront"]

  values = {
    alarms = [
      {
        alarm_name          = "${local.project}-${local.environment}-4xx-errors"
        comparison_operator = "GreaterThanThreshold"
        evaluation_periods  = "2"
        metric_name         = "4xxErrorRate"
        namespace           = "AWS/CloudFront"
        period              = "300"
        statistic           = "Average"
        threshold           = "5"
        alarm_description   = "This metric monitors CloudFront 4xx errors"

        dimensions = {
          DistributionId = unit.cloudfront.outputs.distribution_id
        }
      },
      {
        alarm_name          = "${local.project}-${local.environment}-5xx-errors"
        comparison_operator = "GreaterThanThreshold"
        evaluation_periods  = "2"
        metric_name         = "5xxErrorRate"
        namespace           = "AWS/CloudFront"
        period              = "300"
        statistic           = "Average"
        threshold           = "1"
        alarm_description   = "This metric monitors CloudFront 5xx errors"

        dimensions = {
          DistributionId = unit.cloudfront.outputs.distribution_id
        }
      }
    ]

    # SNS topic for alarm notifications
    sns_topic_arn = try(local.common_values.locals.alerts_topic_arn, null)
  }
}

# Stack outputs
outputs = {
  bucket_name = {
    description = "S3 bucket name for frontend assets"
    value       = unit.s3_bucket.outputs.bucket_id
  }

  cloudfront_distribution_id = {
    description = "CloudFront distribution ID"
    value       = unit.cloudfront.outputs.distribution_id
  }

  cloudfront_domain = {
    description = "CloudFront distribution domain name"
    value       = unit.cloudfront.outputs.distribution_domain_name
  }

  frontend_url = {
    description = "Frontend URL"
    value       = "https://${local.frontend_domain}"
  }

  certificate_arn = {
    description = "ACM certificate ARN"
    value       = unit.acm_certificate.outputs.certificate_arn
  }
}
