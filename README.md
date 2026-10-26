# serverless-pipeline

[![ci](https://github.com/umbra-codex/project-cloud_serverless-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/umbra-codex/project-cloud_serverless-pipeline/actions/workflows/ci.yml)

An event-driven pipeline where an object landing in S3 becomes one queue message and then one DynamoDB row, built with OpenTofu, two Node 24 Lambdas, and a GitHub Actions workflow that plans every push.
