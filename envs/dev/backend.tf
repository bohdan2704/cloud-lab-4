terraform {
  backend "s3" {
    bucket       = "tf-state-lab4-hohol-bohdan-02"
    key          = "envs/dev/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
