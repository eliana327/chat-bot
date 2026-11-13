# =====================================================================
#  El despliegue del chatbot de la tienda de Laura
#  Esumer · Cloud Computing, Redes y Ciberseguridad
#
#  Esta carpeta junta las dos piezas de la solución:
#    back/   → el rol, el permiso a Bedrock, la Lambda y su dirección (Function URL)
#    front/  → el bucket S3 privado, los archivos de la página y CloudFront
#  El front necesita la dirección del back: por eso el back va primero.
#
#  ESTE terraform NO lo corres tú: lo corre el PIPELINE (.github/workflows/pipeline.yml)
#    pull request → terraform plan    (revisar)
#    push a main  → terraform apply   (desplegar) + la prueba en vivo: ¿Lau responde?
#  El estado vive en el bucket S3 que creó el bootstrap, no en ningún PC.
#  Desde tu PC solo para mirar o, al final, para destruir:
#    terraform init -backend-config="bucket=chat-estado-TU-CUENTA"
# =====================================================================

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
  }

  # EL ESTADO REMOTO: un solo estado para el pipeline y para tu PC
  backend "s3" {
    # bucket = chat-estado-TU-CUENTA: lo pasa el pipeline con -backend-config
    key          = "chat/terraform.tfstate" # el archivo del estado dentro del bucket
    region       = "us-east-1"
    encrypt      = true # cifrado en S3
    use_lockfile = true # el candado: terraform.tfstate.tflock mientras alguien aplica
  }
}

provider "aws" {
  region = "us-east-1"
}

# ======================= 1 · EL BACK ==================================
module "back" {
  source = "./back"
  codigo = "${path.module}/../back" # app.py, instrucciones.txt y catalogo.txt
}

# ======================= 2 · EL FRONT =================================
module "front" {
  source   = "./front"
  codigo   = "${path.module}/../front" # index.html, estilos.css y app.js
  chat_url = module.back.direccion     # la dirección del back va en config.js
}

# ======================= LO QUE TE MUESTRA AL TERMINAR ================
output "tu_tienda" {
  description = "Ábrela en el navegador"
  value       = module.front.tienda
}

output "tu_back" {
  description = "La dirección de la Lambda: la usa la página, no se abre en el navegador"
  value       = module.back.direccion
}

output "el_modelo" {
  value = module.back.modelo
}
