# Data Space GitOps

This repository contains GitOps configurations for deploying and managing DS microservices using Fleet and Helm.

## Services

- **Search Service**   
  The Search Service is a service of the Data Space Node, designed to process search queries and aggregate results from decentralized catalogs.

- **Catalog Service**   
  The service provides a REST API for managing, searching, and sharing catalog items.

- **Neo4j With Neosemantics (n10s)**   
  The Neo4j (Enterprise Edition) database with the Neosemantics (n10s) plugin.

- **Frontend**
  The frontend is the user interface of the NextGen Node that allows users to access and interact with its features.

## Structure

- Each service has its own directory containing a `fleet.yaml` file and related Helm values.
- Fleet is used to manage deployments in the `fleet-default` namespace.

## Getting Started

1. Clone this repository.
2. Review and update the `values.yaml` files for each service as needed.
3. Use Fleet to deploy and manage the services in your Kubernetes cluster.

## Requirements

- [Fleet](https://fleet.rancher.io/)
- [Helm](https://helm.sh/)
- Access to the target Kubernetes cluster

## Collaboration guidelines
HIRO uses and requires from its partners [GitFlow with Forks](https://hirodevops.notion.site/GitFlow-with-Forks-3b737784e4fc40eaa007f04aed49bb2e?pvs=4)

## License

This project is maintained by HIRO Microdatacenters BV.