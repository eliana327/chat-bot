# El chatbot de la tienda de Laura

Laboratorio de la clase 17 · Esumer · Cloud Computing, Redes y Ciberseguridad.

La tienda de Laura, con una asistente de servicio al cliente: **Lau** responde con un modelo de
**Amazon Bedrock** (Nova Lite). Todo se crea con Terraform y lo despliega un **pipeline de GitHub Actions**.

```
FRONT   navegador → CloudFront → S3 (la tienda con su chat)
BACK    navegador → Function URL → Lambda (Python) → Amazon Bedrock
```

```
chatbot-laura/
├── front/                ← lo que ve el cliente: se sube a S3 y lo entrega CloudFront
│   ├── index.html           la tienda y la sección "Pregúntale a Lau"
│   ├── estilos.css          el diseño (el mismo de la tienda)
│   └── app.js               manda la charla al back y pinta la respuesta
├── back/                 ← lo que corre en la nube: una función Lambda
│   ├── app.py               recibe la charla y le pregunta al modelo
│   ├── instrucciones.txt    el system prompt: quién es, cómo habla, qué no hace
│   └── catalogo.txt         lo que sabe de la tienda: precios, tallas, envíos
├── bootstrap/            ← lo ÚNICO a mano, una vez: el bucket S3 del estado y los permisos
│   ├── main.tf              el bucket del estado + OIDC + los 2 roles del pipeline
│   └── politica-iam-cicd.json  el permiso que necesita TU usuario terraform-lab para correr main.tf
├── .github/workflows/
│   └── pipeline.yml      ← el pipeline de despliegue, ya parametrizado (sus parámetros arriba, en env:)
├── terraform/            ← el despliegue de la solución (lo aplica el PIPELINE)
│   ├── main.tf              el estado en S3 y las dos piezas: primero el back, después el front
│   ├── back/main.tf         el rol, el permiso a Bedrock, la Lambda y su dirección
│   └── front/main.tf        el bucket S3 privado, los archivos de la página y CloudFront
├── .gitignore            ← lo que NUNCA sube a GitHub: binarios de Terraform (.terraform/), estado, zips, llaves, basura
└── .gitattributes
```

Las instrucciones y el catálogo viven en el **back**: en el front cualquiera los cambiaría con F12.

**Nadie despliega desde su PC.** Como en las clases 13 a 15, el pipeline de GitHub Actions entra a AWS sin llaves (OIDC):

```
pull request → Revisar   : ¿back y front bien escritos? + terraform plan (qué cambiaría)
push a main  → Desplegar : terraform apply + prueba en vivo (¿abre la tienda? ¿Lau responde?)
```

## Antes de empezar

- Cuenta de GitHub y Git instalado (`git --version`), como en la clase 13.
- Terraform 1.10 o más: `terraform version`.
- Tu usuario `terraform-lab` (`aws sts get-caller-identity` debe terminar en `user/terraform-lab`) con
  `AmazonS3FullAccess`, `CloudFrontFullAccess`, `AWSLambda_FullAccess` y la política insertada `solo-roles-y-github`
  de la clase 13 (si no la tienes: IAM → Usuarios → `terraform-lab` → Agregar permisos → Crear política insertada → JSON → pega `bootstrap/politica-iam-cicd.json`).
- Hiciste la exploración de Bedrock por la consola (el modelo Nova Lite te respondió en el playground).

Descomprime el zip en una carpeta nueva (no encima de otro laboratorio) y ábrela en VS Code.
Revisa que tenga la carpeta `.github` (en el Explorador de Windows: Vista → Mostrar → Elementos ocultos).

## PASO 1 · Tu repositorio y el bootstrap

1. GitHub → **New repository** → nombre `chatbot-laura` → **Private** → **no** marques "Add a README" → **Create repository**.
   Copia tu `usuario/chatbot-laura` de la URL, **exacto**.
2. En la terminal de VS Code:

```powershell
cd bootstrap
terraform init
terraform apply      # te pregunta var.repo_github: tu usuario/chatbot-laura · yes
cd ..
```

Menos de 1 minuto: **10 recursos** (el bucket del estado, el proveedor de GitHub y los roles `tienda-chat-plan` y `tienda-chat-apply`).
Al final te muestra **`tu_cuenta`**: tu número de cuenta. Cópialo.

> ¿`EntityAlreadyExists ... oidc-provider`? Tu cuenta ya tiene el proveedor de GitHub:
> `terraform apply -var="crear_proveedor=false"` (9 recursos).

3. En GitHub → tu repositorio → **Settings** → **Secrets and variables** → **Actions** → pestaña **Variables** →
   **New repository variable** → Name `AWS_ACCOUNT_ID` · Value tu número de cuenta → **Add variable**.

## PASO 2 · El primer push: el pipeline despliega

```powershell
git init
git add .
git commit -m "chatbot de Laura"
git branch -M main
git remote add origin https://github.com/TU-USUARIO/chatbot-laura.git
git push -u origin main
```

> Antes del `git push`, `git status` **no** debe mostrar `.terraform/`, `terraform.tfstate` ni `back.zip`:
> el `.gitignore` los deja por fuera (los proveedores de Terraform pesan cientos de MB y el estado describe tu cuenta).

Pestaña **Actions** → **Desplegar (terraform apply + prueba en vivo)**, unos 4 minutos (CloudFront):

- `terraform apply` → `Apply complete! Resources: 16 added`.
- **¿abre la tienda?** y **¿Lau responde?**: el pipeline le pregunta *¿Hacen envíos a Bogotá?* a TU chatbot.
- En el **resumen** de la ejecución: la respuesta de Lau (con sus tokens) y el link de **tu tienda**. Ábrelo.

## PASO 3 · Chatea y mira el viaje

Baja a **Pregúntale a Lau** (o toca una prenda de la colección) y haz estas preguntas:

1. ¿Hacen envíos a Bogotá?
2. ¿Venden zapatos? → no está en el catálogo: debe decir que no, sin inventar
3. ¿Quién ganó el mundial de 2022? → no es de la tienda: no debe responder

Mira el panel **Así viajó tu pregunta** después de cada respuesta:

- **Tokens que leyó**: crece en cada turno, porque viajan otra vez las instrucciones, el catálogo y toda la charla.
- **Mensajes que viajan**: máximo 12; el modelo no recuerda nada, la página le manda la charla completa.

## PASO 4 · Caza el error y arréglalo por pull request

Pulsa **Empezar una charla nueva** y pregunta varias veces (charla nueva cada vez):

> Quiero 2 camisetas y 1 gorra, ¿cuánto es?

La respuesta correcta es **157.000**. A veces el modelo responde otro número, con la misma seguridad:
los modelos de lenguaje no calculan, adivinan la continuación.

Arréglalo con una instrucción, **como un cambio de verdad**: rama → pull request → merge.

```powershell
git checkout -b regla-de-totales
```

Abre `back/instrucciones.txt` y agrega al final:

```
- Para calcular un total, escribe primero la operación paso a paso (cantidad × precio de cada producto, luego la suma) y al final el resultado.
```

```powershell
git add .
git commit -m "regla para calcular totales"
git push -u origin regla-de-totales
```

En GitHub → **Compare & pull request** → **Create pull request**. Corre **Revisar** ✅ y en su resumen:
`Plan: 0 to add, 1 to change, 0 to destroy` (la Lambda: cambió su paquete). **Nada cambió todavía en AWS.**

**Merge pull request** → **Confirm merge** → en **Actions** corre **Desplegar**: `1 changed` y la prueba en vivo.
Recarga la tienda y repite la pregunta: ahora muestra la operación y el total sale bien.

```powershell
git checkout main
git pull
```

## PASO 5 · Cambia lo que sabe y cómo responde (cada cambio, por pull request)

- **Lo que sabe**: en `back/catalogo.txt` agrega `- Medias: 15.000` → rama, PR, merge → pregúntale por las medias.
- **La temperatura**: en `terraform/back/main.tf`, `variable "temperatura"` → `default = 1` → PR (el plan muestra
  `~ TEMPERATURA = "0.3" -> "1"`) → merge → repite una misma pregunta en charlas nuevas.
- **Los logs**: consola → Lambda → `tienda-chat` → Supervisar → Ver registros de CloudWatch.
  Cada respuesta deja una línea con los tokens y los milisegundos.

## PASO 6 · Reto: quítale el permiso

En `terraform/back/main.tf`, bloque `aws_iam_role_policy "bedrock"`: `Effect = "Allow"` → `Effect = "Deny"`. Por pull request:
el plan muestra el cambio de la política. Merge → **Desplegar** falla en **¿Lau responde?** con `AccessDeniedException`:
**el pipeline atajó el error antes que un cliente**. Devuélvelo a `"Allow"` con otro pull request.

## Al terminar (¡importante!)

La dirección del back es pública: no la dejes prendida. Desde tu PC, en la carpeta principal (cambia `TU-CUENTA`):

```powershell
cd terraform
terraform init -backend-config="bucket=chat-estado-TU-CUENTA"
terraform destroy    # yes · tarda unos 3 minutos (CloudFront) · Resources: 16 destroyed

cd ../bootstrap
terraform destroy    # yes · el bucket del estado, el proveedor de GitHub y los roles

aws logs delete-log-group --log-group-name /aws/lambda/tienda-chat
```

## Si algo falla

| Lo que ves | Qué es | Qué hacer |
|---|---|---|
| `AccessDeniedException` en el chat | el rol no puede llamar al modelo, o tu cuenta no tiene acceso al modelo | revisa el bloque `bedrock` de `terraform/back/main.tf`; prueba el modelo en el playground de la consola |
| `ThrottlingException` en el chat | muchas preguntas seguidas para la cuota de tu cuenta | espera un minuto y vuelve a preguntar |
| "No hubo conexión con el back" | la Lambda o su dirección aún no quedan listas | espera unos segundos y vuelve a preguntar |
| `Falta la variable AWS_ACCOUNT_ID` (en Actions) | no creaste la variable del PASO 1 | créala y en Actions → **Re-run all jobs** |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | el repositorio quedó mal escrito en el bootstrap, o la variable tiene otro número | en `bootstrap`: `terraform apply -var="repo_github=TU-USUARIO/chatbot-laura"`; revisa la variable |
| `AccessDenied ... CreateRole` o `CreateOpenIDConnectProvider` (bootstrap) | a `terraform-lab` le falta `solo-roles-y-github` | créala con `bootstrap/politica-iam-cicd.json` (la misma de la clase 13) |
| `BucketAlreadyOwnedByYou` (bootstrap) | ya corriste el bootstrap en otra carpeta | corre `terraform destroy` allá, o borra el bucket `chat-estado-…` (vacíalo primero) |
| `EntityAlreadyExists` o `ResourceConflictException` (en Desplegar) | quedó un `tienda-chat` de un intento anterior | en esa carpeta: `terraform destroy`; o bórralo en la consola (Lambda y el rol `tienda-chat-lambda`) |
| `terraform fmt -check` ❌ en Revisar | quedó mal alineado un `=` | en tu PC: `terraform fmt -recursive terraform`, commit y push a la misma rama |
| `refusing to allow ... workflow ... without workflow scope` | tu token de Git no tiene permiso `workflow` | Administrador de credenciales → borra `git:https://github.com` → `git push` otra vez |
| No ves la carpeta `.github` | Windows oculta las carpetas con punto | Vista → Mostrar → Elementos ocultos; si no está, vuelve a descomprimir el zip |
| La página muestra `AccessDenied` (XML) | CloudFront recién creado | espera un minuto y recarga |
