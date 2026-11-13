# =====================================================================
#  EL BACK: navegador → Function URL → Lambda (Python) → Amazon Bedrock
#  El código está en la carpeta back/ del repositorio (app.py y los dos textos).
# =====================================================================

terraform {
  required_providers {
    aws     = { source = "hashicorp/aws" }
    archive = { source = "hashicorp/archive" }
  }
}

variable "codigo" {
  description = "La carpeta con app.py, instrucciones.txt y catalogo.txt"
  type        = string
}

# ======================= LO QUE PUEDES CAMBIAR ========================
# El modelo de Bedrock: el mismo ID que viste en la consola (Catálogo de modelos)
variable "modelo" {
  type    = string
  default = "amazon.nova-micro-v1:0" # más barato y rápido: amazon.nova-micro-v1:0
}

# Temperatura: 0 = siempre la respuesta más probable · 1 = más variada y creativa
variable "temperatura" {
  type    = number
  default = 0.3 # servicio al cliente: baja, para que no improvise
}

# ======================= 1 · EL ROL DE LA LAMBDA: quién es ============
resource "aws_iam_role" "chat" {
  name = "tienda-chat-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 2 · Qué puede hacer: escribir sus logs…
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.chat.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 3 · …y llamar a UN solo modelo de Bedrock (mínimo privilegio).
#     Sin este permiso el chat responde AccessDeniedException.
resource "aws_iam_role_policy" "bedrock" {
  name = "solo-este-modelo"
  role = aws_iam_role.chat.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock:InvokeModel"
      Resource = "arn:aws:bedrock:us-east-1::foundation-model/${var.modelo}"
    }]
  })
}

# ======================= 4 · EL PAQUETE: la carpeta back/ en un zip ===
data "archive_file" "back" {
  type        = "zip"
  source_dir  = var.codigo
  output_path = "${path.module}/back.zip"

  output_file_mode = "0644" # los mismos permisos en Windows, Mac y Linux: la Lambda puede leer los archivos
}

# ======================= 5 · LA FUNCIÓN LAMBDA ========================
resource "aws_lambda_function" "chat" {
  function_name    = "tienda-chat"
  role             = aws_iam_role.chat.arn
  runtime          = "python3.12"
  handler          = "app.handler"
  filename         = data.archive_file.back.output_path
  source_code_hash = data.archive_file.back.output_base64sha256 # si cambia un archivo de back/, se vuelve a subir
  timeout          = 30                                         # el modelo puede tardar unos segundos
  memory_size      = 256

  environment {
    variables = {
      MODELO      = var.modelo
      TEMPERATURA = tostring(var.temperatura)
    }
  }

  depends_on = [aws_iam_role_policy_attachment.logs, aws_iam_role_policy.bedrock]
}

# ======================= 6 · LA PUERTA: una dirección HTTPS (sin API Gateway)
resource "aws_lambda_function_url" "chat" {
  function_name      = aws_lambda_function.chat.function_name
  authorization_type = "NONE" # pública: la llama el navegador (y la prueba del pipeline). Por eso se destruye al terminar.

  cors { # deja que la página (otro dominio: CloudFront) le hable
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
  }
}

resource "aws_lambda_permission" "url" {
  statement_id           = "puerta-publica"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.chat.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invocar" {
  statement_id             = "puerta-publica-invocar"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.chat.function_name
  principal                = "*"
  invoked_via_function_url = true
}

# ======================= LO QUE LE ENTREGA AL FRONT ===================
output "direccion" {
  value = aws_lambda_function_url.chat.function_url
}

output "modelo" {
  value = "${var.modelo} · temperatura ${var.temperatura}"
}
