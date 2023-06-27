terraform {
  backend "s3" {
    bucket  = ""
    encrypt = true
    key     = "terraform.tfstate"
    region  = ""
  }
}
