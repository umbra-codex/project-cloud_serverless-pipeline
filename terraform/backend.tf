terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "tfstate-774493573314-serverless"
    key          = "serverless-pipeline/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
