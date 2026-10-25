output "ci_role_arn" {
  description = "ARN of the role GitHub Actions assumes through OIDC"
  value       = aws_iam_role.ci_plan.arn
}
