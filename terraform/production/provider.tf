provider "aws" {
  region  = "us-east-1"
  version = "~> 3.9.0"
  profile = "dumpster"
}

provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
  version = "~> 3.9.0"
  profile = "dumpster"
}

provider "aws" {
  alias   = "us-east-2"
  region  = "us-east-2"
  version = "~> 3.9.0"
  profile = "dumpster"
}

provider "aws" {
  alias   = "us-west-1"
  region  = "us-west-1"
  version = "~> 3.9.0"
  profile = "dumpster"
}

provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
  version = "~> 3.9.0"
  profile = "dumpster"
}
