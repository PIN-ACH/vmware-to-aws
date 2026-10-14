# ─────────────────────────────────────────────────────────────────────────────
# IAM: EC2 instance profile (SSM-manageable instances) and the DMS roles.
#
# NOTE: Requires iam:PassRole and iam:CreateServiceLinkedRole on the deploying
# principal (see docs/OPERATIONS.md permissions section).
# ─────────────────────────────────────────────────────────────────────────────

# ---- EC2 instance role (allows SSM Session Manager + CloudWatch agent) ------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ---- DMS roles --------------------------------------------------------------
# DMS requires a role named exactly "dms-vpc-role" the first time it is used in
# an account, to manage VPC settings. Created here if absent.
data "aws_iam_policy_document" "dms_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dms_vpc" {
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  tags               = { Note = "Required by AWS DMS for VPC management" }
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms_vpc.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}
