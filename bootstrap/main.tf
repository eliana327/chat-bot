# =====================================================================
#  BOOTSTRAP del chatbot · lo ÚNICO que corres a mano, una sola vez
#  Esumer · Cloud Computing, Redes y Ciberseguridad
#
#  Aquí NO se despliega la solución (eso es terraform/, y lo hace el pipeline).
#  Aquí solo va lo que el pipeline necesita ANTES de su primer push:
#
#    EL BUCKET S3
#      1 · el bucket del ESTADO de Terraform (con versiones, cifrado y candado)
#    LOS PERMISOS
#      2 · el proveedor OIDC de GitHub: el pipeline entra a AWS sin llaves
#      3 · el rol tienda-chat-plan   → lo usa cada PULL REQUEST (solo mirar)
#      4 · el rol tienda-chat-apply  → lo usa cada push a MAIN (desplegar, solo el chatbot)
#  El pipeline (.github/workflows/pipeline.yml) solo necesita tu número de cuenta,
#  que este bootstrap te muestra al terminar.
#
#  terraform apply crea TODO esto solo (10 recursos): el bucket, el proveedor OIDC,
#  los 2 roles y sus políticas (solo-el-candado, solo-el-chatbot y ReadOnlyAccess).
#
#  politica-iam-cicd.json (en esta carpeta) NO es para el pipeline: es el permiso de
#  TU usuario terraform-lab para poder correr este apply. Ya lo tienes desde la clase 13
#  (solo-roles-y-github). Solo si el apply dice AccessDenied ... CreateRole, pégala en
#  IAM → Usuarios → terraform-lab → Agregar permisos → Crear política insertada → JSON.
#  (No puede crearla este mismo terraform: la necesita para correr.)
#
#  Uso (terminal de VS Code, DENTRO de esta carpeta bootstrap):
#    terraform init
#    terraform apply      (te pregunta tu repositorio de GitHub · menos de 1 minuto)
#  Su estado queda en ESTE PC (terraform.tfstate): no borres esta carpeta
#  hasta el final del lab.
# =====================================================================

terraform {
  required_version = ">= 1.10" # use_lockfile (el candado en S3) llegó en la 1.10
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ======================= TUS DATOS ====================================
variable "repo_github" {
  description = "Tu repositorio de GitHub como usuario/repositorio, copiado EXACTO de la URL (ejemplo: camila-perez/chatbot-laura)"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.repo_github))
    error_message = "Escríbelo como usuario/repositorio, sin https://github.com/ (ejemplo: camila-perez/chatbot-laura)."
  }
}

variable "crear_proveedor" {
  description = "true = crea el proveedor OIDC de GitHub en tu cuenta · false = ya existe (EntityAlreadyExists) y se reutiliza"
  type        = bool
  default     = true
}

data "aws_caller_identity" "yo" {}

locals {
  cuenta = data.aws_caller_identity.yo.account_id
  estado = "chat-estado-${local.cuenta}" # el número de cuenta lo hace único en el mundo
}

# ======================= EL BUCKET S3: 1 · EL ESTADO ==================
resource "aws_s3_bucket" "estado" {
  bucket        = local.estado
  force_destroy = true # permite borrarlo aunque tenga archivos (solo para el lab)
}

# cada apply guarda una VERSIÓN nueva del estado
resource "aws_s3_bucket_versioning" "estado" {
  bucket = aws_s3_bucket.estado.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "estado" {
  bucket                  = aws_s3_bucket.estado.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ======================= LOS PERMISOS: 2 · OIDC, GitHub entra SIN llaves
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.crear_proveedor ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.crear_proveedor ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  proveedor_arn = var.crear_proveedor ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # GitHub firma el pase con un "sub" que dice QUIÉN pide entrar. Dos formatos:
  #   viejo: repo:usuario/repo:ref:refs/heads/main
  #   nuevo: repo:usuario@123/repo@456:ref:refs/heads/main
  dueno = split("/", var.repo_github)[0]
  repo  = split("/", var.repo_github)[1]

  confianza = {
    for rol, evento in {
      plan  = "pull_request"        # un pull request
      apply = "ref:refs/heads/main" # un push a main
      } : rol => jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = { Federated = local.proveedor_arn }
          Action    = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
            StringLike = { "token.actions.githubusercontent.com:sub" = [
              "repo:${var.repo_github}:${evento}",
              "repo:${local.dueno}@*/${local.repo}@*:${evento}",
            ] }
          }
        }]
    })
  }
}

# ======================= 3 · EL ROL DEL PULL REQUEST: solo mirar ======
resource "aws_iam_role" "plan" {
  name               = "tienda-chat-plan"
  assume_role_policy = local.confianza.plan
}

resource "aws_iam_role_policy_attachment" "plan_leer" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# lo único que escribe: el candado del estado (mientras corre el plan)
resource "aws_iam_role_policy" "plan_candado" {
  name = "solo-el-candado"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PonerYQuitarElCandado"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.estado.arn}/chat/terraform.tfstate.tflock"
    }]
  })
}

# ======================= 4 · EL ROL DE MAIN: desplegar el chatbot =====
resource "aws_iam_role" "apply" {
  name               = "tienda-chat-apply"
  assume_role_policy = local.confianza.apply
}

# SOLO los recursos del chatbot: la Lambda tienda-chat, el bucket tienda-laura-chat-…,
# CloudFront y el rol de la Lambda. Fíjate: el pipeline NO tiene bedrock:InvokeModel;
# solo puede dárselo al rol de la Lambda (y solo ese rol).
resource "aws_iam_role_policy" "apply" {
  name = "solo-el-chatbot"
  role = aws_iam_role.apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "VerElEstado", Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.estado.arn },
      { Sid = "LeerYGuardarElEstado", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.estado.arn}/chat/*" },
      { Sid = "LaLambda", Effect = "Allow", Action = ["lambda:*"], Resource = "arn:aws:lambda:us-east-1:${local.cuenta}:function:tienda-chat" },
      { Sid = "ElBucketDelFront", Effect = "Allow", Action = ["s3:*"], Resource = ["arn:aws:s3:::tienda-laura-chat-*", "arn:aws:s3:::tienda-laura-chat-*/*"] },
      { Sid = "CloudFront", Effect = "Allow", Action = ["cloudfront:*"], Resource = "*" },
      {
        Sid    = "ElRolDeLaLambda"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::${local.cuenta}:role/tienda-chat-lambda"
      },
      {
        Sid       = "SoloLaPoliticaDeLogs"
        Effect    = "Allow"
        Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource  = "arn:aws:iam::${local.cuenta}:role/tienda-chat-lambda"
        Condition = { ArnEquals = { "iam:PolicyARN" = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" } }
      },
      {
        Sid       = "PasarleElRolALaLambda"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = "arn:aws:iam::${local.cuenta}:role/tienda-chat-lambda"
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      }
    ]
  })
}

# ======================= LO QUE TE MUESTRA AL TERMINAR ================
output "bucket_del_estado" {
  value = aws_s3_bucket.estado.id
}

output "rol_plan" {
  value = aws_iam_role.plan.arn
}

output "rol_apply" {
  value = aws_iam_role.apply.arn
}

output "tu_cuenta" {
  description = "Cópialo en GitHub → Settings → Secrets and variables → Actions → Variables → AWS_ACCOUNT_ID"
  value       = local.cuenta
}
