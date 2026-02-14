terraform {
  backend "s3" {
    # Configuration will be provided via -backend-config flags in deploy.sh
    # bucket         = "twin-terraform-state-<account-id>"
    # key            = "twin/<environment>/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "twin-terraform-locks"
    # encrypt        = true
  }
}
