# Rol que asumen las instancias del Auto Scaling Group.
# Les permite leer SOLO sus parámetros de SSM (.env y deploy key) y usar Session Manager.

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${local.name_prefix}-app-role" }
}

# Lectura de los parámetros de la app (cifrados con la llave administrada aws/ssm)
data "aws_iam_policy_document" "app_ssm_read" {
  statement {
    actions = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*",
    ]
  }
}

resource "aws_iam_role_policy" "app_ssm_read" {
  name   = "read-app-parameters"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_ssm_read.json
}

# Session Manager: acceso de emergencia a las instancias desde la consola, sin SSH
resource "aws_iam_role_policy_attachment" "app_ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}
