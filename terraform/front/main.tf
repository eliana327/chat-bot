# =====================================================================
#  EL FRONT: navegador → CloudFront (HTTPS) → S3 privado (la tienda con su chat)
#  Los archivos están en la carpeta front/ del repositorio.
# =====================================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "codigo" {
  description = "La carpeta con index.html, estilos.css y app.js"
  type        = string
}

variable "chat_url" {
  description = "La dirección del back (la Function URL de la Lambda)"
  type        = string
}

locals {
  tipos = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "application/javascript; charset=utf-8"
  }
}

# ======================= 1 · EL BUCKET S3 PRIVADO =====================
resource "aws_s3_bucket" "front" {
  bucket_prefix = "tienda-laura-chat-"
  force_destroy = true # permite borrarlo aunque tenga archivos (solo para el lab)
}

resource "aws_s3_bucket_public_access_block" "front" {
  bucket                  = aws_s3_bucket.front.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ======================= 2 · LOS ARCHIVOS DE LA PÁGINA ================
# sube TODOS los archivos de front/ (index.html, estilos.css, app.js)
resource "aws_s3_object" "front" {
  for_each     = fileset(var.codigo, "**")
  bucket       = aws_s3_bucket.front.id
  key          = each.value
  source       = "${var.codigo}/${each.value}"
  etag         = filemd5("${var.codigo}/${each.value}")
  content_type = lookup(local.tipos, reverse(split(".", each.value))[0], "application/octet-stream")
}

# config.js: le dice a la página cuál es la dirección de TU back
resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.front.id
  key          = "config.js"
  content      = "window.CHAT_URL = \"${var.chat_url}\";\n"
  content_type = "application/javascript; charset=utf-8"
}

# ======================= 3 · CLOUDFRONT: HTTPS al mundo ===============
# solo CloudFront puede leer el bucket (OAC)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac-${aws_s3_bucket.front.id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  comment             = "Tienda de Laura con chatbot"

  origin {
    domain_name              = aws_s3_bucket.front.bucket_regional_domain_name
    origin_id                = "s3-tienda"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-tienda"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled: ves tus cambios al instante
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "solo_cloudfront" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.front.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "front" {
  bucket     = aws_s3_bucket.front.id
  policy     = data.aws_iam_policy_document.solo_cloudfront.json
  depends_on = [aws_s3_bucket_public_access_block.front]
}

# ======================= LO QUE ENTREGA ===============================
output "tienda" {
  value = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}
