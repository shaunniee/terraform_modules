module "s3" {
    source = "git::https://github.com/shaunniee/terraform_modules.git//aws_s3?ref=main"
    bucket_name = "my-unique-bucket-name"
  
}