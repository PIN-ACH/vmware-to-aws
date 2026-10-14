# ─────────────────────────────────────────────────────────────────────────────
# Security groups per tier. Rules mirror engine/mapping.yaml:
#   web: 80/443 from internet, 22 from VPC
#   app: 8080 from web SG, 22 from VPC
#   db:  5432 from app SG, 22 from VPC
# Using SG-to-SG references (not CIDRs) for tier-to-tier traffic is the AWS
# best-practice equivalent of vSphere port-group isolation.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "web" {
  name        = "${var.project}-web"
  description = "Web tier"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-web", Tier = "web" }
}

resource "aws_security_group" "app" {
  name        = "${var.project}-app"
  description = "App tier"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-app", Tier = "app" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "DB tier"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-db", Tier = "db" }
}

# ---- Web ingress -----------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from internet"
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from internet"
}

resource "aws_vpc_security_group_ingress_rule" "web_ssh" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = var.ssh_ingress_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from VPC"
}

# ---- App ingress -----------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "app_api" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.web.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "API from web tier"
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = var.ssh_ingress_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from VPC"
}

# ---- DB ingress ------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "db_postgres" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from app tier"
}

resource "aws_vpc_security_group_ingress_rule" "db_ssh" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = var.ssh_ingress_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "SSH from VPC"
}

# ---- Egress: allow all outbound for every tier -----------------------------
resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

resource "aws_vpc_security_group_egress_rule" "db_all" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}
