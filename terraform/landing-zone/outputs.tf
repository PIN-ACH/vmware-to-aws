# ─────────────────────────────────────────────────────────────────────────────
# Outputs consumed by downstream steps (generated workloads, Ansible inventory,
# DMS module). The engine reads these via `terraform output -json`.
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Map of subnet name -> id (public)."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "Map of subnet name -> id (private)."
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "security_group_ids" {
  description = "Per-tier security group ids keyed by role."
  value = {
    web = aws_security_group.web.id
    app = aws_security_group.app.id
    db  = aws_security_group.db.id
  }
}

output "ec2_instance_profile" {
  value = aws_iam_instance_profile.ec2.name
}

output "region" {
  value = var.region
}
