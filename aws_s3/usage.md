# AWS S3 Bucket Terraform Module

A comprehensive Terraform module for creating and managing AWS S3 buckets with support for versioning, encryption, lifecycle policies, CORS, logging, and replication.

## Features

- ✅ **Automatic Versioning**: Enabled by default for data protection
- 🔒 **Server-Side Encryption**: Support for AES256 and AWS KMS
- 🔐 **Private by Default**: Public access blocked by default
- 🛡️ **Lifecycle Protection**: Optional prevent_destroy lifecycle policy
- 📝 **Access Logging**: Optional logging to managed or external buckets
- 🔁 **Cross-Region Replication**: With automatic IAM role creation
- 🌐 **CORS Configuration**: Support for multiple CORS rules
- ♻️ **Lifecycle Management**: Transitions and expiration policies

## Basic Usage

### Minimal Configuration

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-application-bucket"
}
```

This creates a private S3 bucket with:
- Versioning enabled
- AES256 encryption
- Public access blocked
- Prevent destroy lifecycle policy

### Custom Configuration

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name      = "my-application-bucket"
  prevent_destroy  = true
  force_destroy    = false
  private_bucket   = true
  
  server_side_encryption = {
    enabled              = true
    encryption_algorithm = "AES256"
    kms_master_key_id    = null
  }
}
```

## Advanced Features

### 1. KMS Encryption

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-encrypted-bucket"
  
  server_side_encryption = {
    enabled              = true
    encryption_algorithm = "aws:kms"
    kms_master_key_id    = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  }
}
```

### 2. Lifecycle Rules

Manage object transitions and expiration:

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-bucket-with-lifecycle"
  
  lifecycle_rules = [
    {
      id      = "archive-old-objects"
      enabled = true
      
      filter = {
        prefix = "documents/"
      }
      
      transition = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      
      expiration = {
        days = 365
      }
    },
    {
      id      = "cleanup-old-versions"
      enabled = true
      
      noncurrent_version_transition = [
        {
          noncurrent_days = 30
          storage_class   = "GLACIER"
        }
      ]
      
      noncurrent_version_expiration = [
        {
          noncurrent_days = 90
        }
      ]
    }
  ]
}
```

**Available Storage Classes:**
- `STANDARD_IA` - Infrequent Access
- `ONEZONE_IA` - One Zone Infrequent Access
- `INTELLIGENT_TIERING` - Automatic tiering
- `GLACIER` - Glacier storage
- `DEEP_ARCHIVE` - Glacier Deep Archive

### 3. CORS Configuration

Enable cross-origin resource sharing:

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-static-website-bucket"
  
  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = ["https://example.com", "https://www.example.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["Authorization"]
      allowed_methods = ["POST", "PUT"]
      allowed_origins = ["https://app.example.com"]
      max_age_seconds = 3600
    }
  ]
}
```

### 4. Access Logging

#### With Managed Logging Bucket

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-application-bucket"
  
  logging = {
    enabled        = true
    managed_bucket = true
    target_bucket  = ""
    target_prefix  = ""  # Defaults to "logs/"
  }
}
```

This automatically creates a `${bucket_name}-logs` bucket.

#### With External Logging Bucket

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-application-bucket"
  
  logging = {
    enabled        = true
    managed_bucket = false
    target_bucket  = "my-centralized-logging-bucket"
    target_prefix  = "s3-logs/my-application-bucket/"
  }
}
```

### 5. Cross-Region Replication

Replicate objects to another bucket with automatic IAM role creation:

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-source-bucket"
  
  replication = {
    role_arn = ""  # Leave empty to auto-create IAM role
    
    rules = [
      {
        id                     = "replicate-all"
        prefix                 = ""  # Empty = replicate entire bucket
        status                 = "Enabled"
        destination_bucket_arn = "arn:aws:s3:::my-destination-bucket-in-us-west-2"
        storage_class          = "STANDARD"
      },
      {
        id                     = "replicate-docs"
        prefix                 = "documents/"
        status                 = "Enabled"
        destination_bucket_arn = "arn:aws:s3:::my-docs-backup-bucket"
        storage_class          = "STANDARD_IA"
      }
    ]
  }
}
```

**Requirements:**
- Source bucket must have versioning enabled (automatic in this module)
- Destination bucket must exist and have versioning enabled
- Destination bucket ARN is **mandatory**

**With Existing IAM Role:**

```hcl
module "s3_bucket" {
  source = "./aws_s3"
  
  bucket_name = "my-source-bucket"
  
  replication = {
    role_arn = "arn:aws:iam::123456789012:role/my-existing-replication-role"
    
    rules = [
      {
        id                     = "main-replication"
        status                 = "Enabled"
        destination_bucket_arn = "arn:aws:s3:::my-destination-bucket"
        storage_class          = "STANDARD"
      }
    ]
  }
}
```

## Input Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `bucket_name` | string | - | ✅ Yes | The name of the S3 bucket |
| `force_destroy` | bool | `false` | No | Allow bucket deletion even with objects inside |
| `private_bucket` | bool | `true` | No | Block all public access |
| `prevent_destroy` | bool | `true` | No | Prevent accidental bucket deletion via Terraform |
| `server_side_encryption` | object | See below | No | Server-side encryption configuration |
| `lifecycle_rules` | list(object) | `[]` | No | Lifecycle management rules |
| `cors_rules` | list(object) | `[]` | No | CORS configuration rules |
| `logging` | object | Disabled | No | Access logging configuration |
| `replication` | object | `null` | No | Cross-region replication configuration |

### server_side_encryption Object

```hcl
{
  enabled              = bool
  encryption_algorithm = string  # "AES256" or "aws:kms"
  kms_master_key_id    = string  # Required if using KMS
}
```

**Default:**
```hcl
{
  enabled              = true
  encryption_algorithm = "AES256"
  kms_master_key_id    = null
}
```

### lifecycle_rules Object

```hcl
{
  id      = string
  enabled = bool  # Default: true
  
  filter = {
    prefix = string  # Optional
    tag = {
      key   = string
      value = string
    }
  }
  
  transition = [
    {
      days          = number
      storage_class = string
    }
  ]
  
  noncurrent_version_transition = [
    {
      noncurrent_days = number
      storage_class   = string
    }
  ]
  
  expiration = {
    days                         = number
    expired_object_delete_marker = bool
  }
  
  noncurrent_version_expiration = [
    {
      noncurrent_days = number
    }
  ]
}
```

### cors_rules Object

```hcl
{
  allowed_headers = list(string)
  allowed_methods = list(string)  # GET, PUT, POST, DELETE, HEAD
  allowed_origins = list(string)
  expose_headers  = list(string)  # Optional
  max_age_seconds = number        # Default: 3000
}
```

### logging Object

```hcl
{
  enabled        = bool
  managed_bucket = bool    # true = auto-create logging bucket
  target_bucket  = string  # Required if managed_bucket = false
  target_prefix  = string  # Default: "logs/" for managed, "" otherwise
}
```

### replication Object

```hcl
{
  role_arn = string  # Optional: empty = auto-create IAM role
  
  rules = [
    {
      id                     = string
      prefix                 = string  # Optional: empty = entire bucket
      status                 = string  # "Enabled" or "Disabled"
      destination_bucket_arn = string  # Required: ARN of destination bucket
      storage_class          = string  # STANDARD, STANDARD_IA, etc.
    }
  ]
}
```

## Outputs

| Output | Description |
|--------|-------------|
| `bucket_id` | The name of the S3 bucket |
| `bucket_arn` | The ARN of the S3 bucket |
| `bucket_domain_name` | The bucket domain name |
| `bucket_regional_domain_name` | The bucket region-specific domain name |
| `bucket_region` | The AWS region where the bucket was created |
| `versioning_enabled` | Whether versioning is enabled (always true) |
| `encryption_enabled` | Whether server-side encryption is enabled |
| `encryption_algorithm` | The encryption algorithm used |
| `is_private_bucket` | Whether public access is blocked |
| `logging_enabled` | Whether logging is enabled |
| `logging_bucket_id` | The ID of the managed logging bucket (if created) |
| `logging_bucket_arn` | The ARN of the managed logging bucket (if created) |
| `logging_target_bucket` | The target bucket for logs |
| `replication_enabled` | Whether replication is configured |
| `replication_role_arn` | The ARN of the replication IAM role |
| `replication_role_name` | The name of the auto-created replication role |
| `replication_rules` | List of replication rule IDs |
| `lifecycle_rules_count` | Number of lifecycle rules configured |
| `cors_rules_count` | Number of CORS rules configured |

## Complete Example

```hcl
module "production_bucket" {
  source = "./aws_s3"
  
  bucket_name     = "my-production-app-data"
  prevent_destroy = true
  force_destroy   = false
  private_bucket  = true
  
  server_side_encryption = {
    enabled              = true
    encryption_algorithm = "aws:kms"
    kms_master_key_id    = aws_kms_key.s3.arn
  }
  
  lifecycle_rules = [
    {
      id      = "intelligent-tiering"
      enabled = true
      
      transition = [
        {
          days          = 30
          storage_class = "INTELLIGENT_TIERING"
        }
      ]
      
      noncurrent_version_expiration = [
        {
          noncurrent_days = 30
        }
      ]
    }
  ]
  
  logging = {
    enabled        = true
    managed_bucket = false
    target_bucket  = "my-centralized-logs"
    target_prefix  = "s3-access-logs/production/"
  }
  
  replication = {
    role_arn = ""
    
    rules = [
      {
        id                     = "disaster-recovery"
        prefix                 = ""
        status                 = "Enabled"
        destination_bucket_arn = "arn:aws:s3:::my-dr-bucket-us-west-2"
        storage_class          = "STANDARD"
      }
    ]
  }
  
  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = ["https://app.example.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]
}

# Access outputs
output "bucket_name" {
  value = module.production_bucket.bucket_id
}

output "bucket_arn" {
  value = module.production_bucket.bucket_arn
}

output "replication_role" {
  value = module.production_bucket.replication_role_arn
}
```

## Notes

### Bucket Naming

- Bucket names must be globally unique across all AWS accounts
- Must be 3-63 characters long
- Can contain lowercase letters, numbers, hyphens, and periods
- Must start and end with a letter or number

### Best Practices

1. **Enable versioning** (automatic in this module) for data protection
2. **Use KMS encryption** for sensitive data
3. **Enable logging** for audit trails
4. **Configure lifecycle rules** to optimize storage costs
5. **Use replication** for disaster recovery and compliance
6. **Keep prevent_destroy = true** for production buckets
7. **Use least-privilege IAM policies** when accessing the bucket

### Cost Optimization

- Use lifecycle rules to transition objects to cheaper storage classes
- Enable Intelligent Tiering for unpredictable access patterns
- Set expiration policies for temporary data
- Monitor storage metrics with CloudWatch

### Security Considerations

- Always use encryption (enabled by default)
- Keep buckets private unless specifically needed
- Enable logging for security auditing
- Use bucket policies and IAM roles for access control
- Enable MFA Delete for additional protection (requires AWS CLI configuration)

## Troubleshooting

### Replication Not Working

1. Ensure destination bucket exists and has versioning enabled
2. Verify IAM role has correct permissions
3. Check that source and destination are in different regions (for CRR)
4. Confirm destination bucket ARN is in correct format

### Lifecycle Rules Not Applying

1. Verify rule status is "Enabled"
2. Check filter prefix matches your object keys
3. Ensure transition days are in ascending order
4. Wait up to 24 hours for rules to take effect

### Access Denied Errors

1. Check bucket policy and IAM permissions
2. Verify public access block settings
3. Confirm encryption key permissions (if using KMS)
4. Review VPC endpoint policies (if using VPC endpoints)

## Version Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0

## License

This module is provided as-is for use in your infrastructure.
