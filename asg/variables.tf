variable "region" {
  type = string
  description = "Region to deploy"
}

variable "profile" {
  type = string
  description = "profile to use"
}

variable "vpc_cidr" {
  description = "vpc cidr"
  type = string
  default = "10.0.0.0/16"
}

variable "vpc_name" {
  type = string
  description = "vpc name"
  default = "scaling"
}

variable "cluster_name" {
  type = string
  description = "Cluster name"
  default = "scaling"
}