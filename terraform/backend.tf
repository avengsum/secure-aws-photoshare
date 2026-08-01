terraform {

  backend "s3" {

    bucket = "state-terraform-state-2026"

    key = "secure-photoshare/terraform.tfstate"

    region = "us-east-1"

    dynamodb_table = "terraform-locks"

    encrypt = true

  }

}