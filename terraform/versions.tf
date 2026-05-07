terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.45.1"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "put your subscription here"
}
