# aws-bash-toolbox (AWS CLI + SSO + SSM) 🧰

Toolkit para **Bash** que te da una experiencia estilo `kubectx/kubens` pero para AWS:

- Contexto activo: `AWS_PROFILE` + `AWS_REGION` (persistente)
- Cambiar rápido profile/región: `awsp`, `awsr`, `awsctx`, `awsctxf` (con `fzf`)
- Listar instancias EC2 sin consola web: `ec2ls`
- Conectar por **SSM Session Manager** sin SSH: `ssm`, `ssmfzf`
- Workaround para entornos corporativos: SSM ignora proxy/VPN **solo** cuando abre sesión

Este repo incluye:
- `awsctx.sh` → todas las funciones Bash (lo importante)
- `install.sh` → instalador (añade `source .../awsctx.sh` a tu `~/.bashrc`)

---

## Requisitos

- Ubuntu 24.04
- Bash
- AWS CLI v2
- Acceso por IAM Identity Center (SSO)

Instala dependencias:

```bash
sudo apt update
sudo apt install -y fzf session-manager-plugin
```

Comprueba:

```bash
aws --version         # debe ser aws-cli/2.x
session-manager-plugin
```

---

## Convención de perfiles (recomendada)

Usamos:

**`corp-<env>-<role>`**

Ejemplos:

* `corp-dev-readonly`
* `corp-uat-admin`
* `corp-pro-support`

Donde:

* `<env>`: entorno objetivo (por ejemplo: `dev`, `uat`, `pro`)
* `<role>`: permission set o rol en IAM Identity Center (por ejemplo: `admin`, `readonly`, `support`)

> Si vuestro equipo usa otros names (`sandbox`, `np`, `prod`, etc.), se puede adaptar.
> Lo importante es que el naming sea consistente.

---

## 1) Configurar AWS SSO (perfiles)

Este toolbox asume perfiles AWS basados en SSO en `~/.aws/config`.

### 1.1 Crear/validar la sesión SSO

En `~/.aws/config`:

```ini
[sso-session corp-sso]
sso_start_url = https://<TU_START_URL>/start
sso_region = eu-central-1
sso_registration_scopes = sso:account:access
```

**Importante**: usa el Start URL sin `/#/` para evitar problemas de token/caché.

### 1.2 Crear perfiles por cuenta y role (permission set)

Ejemplos completos:

```ini
[profile corp-dev-admin]
sso_session = corp-sso
sso_account_id = 111111111111
sso_role_name = admin
region = eu-west-3
output = json

[profile corp-uat-readonly]
sso_session = corp-sso
sso_account_id = 222222222222
sso_role_name = readonly
region = eu-west-3
output = json

[profile corp-pro-support]
sso_session = corp-sso
sso_account_id = 333333333333
sso_role_name = support
region = eu-west-3
output = json
```

> Nota: en SSO lo correcto es `sso_session + sso_account_id + sso_role_name`.
> Evita `source_profile + role_arn` (AssumeRole clásico), salvo que tu organización lo requiera expresamente.

---

## 2) Login SSO

Si has tocado perfiles o tuviste errores:

```bash
rm -rf ~/.aws/sso/cache/*
```

Login:

```bash
aws sso login --sso-session corp-sso
```

Verifica:

```bash
aws sts get-caller-identity --profile corp-dev-admin --region eu-west-3
```

---

## 3) Instalación del toolbox

### Método A) Instalación automática (recomendada)

```bash
git clone https://github.com/sondosclick/aws-bash-toolbox
cd aws-bash-toolbox
./install.sh
source ~/.bashrc
```

Qué hace `install.sh`:

* añade en tu `~/.bashrc` una línea tipo:

```bash
source "<RUTA_DEL_REPO>/awsctx.sh"
```

No sobrescribe tu bashrc y es seguro ejecutarlo varias veces.

### Método B) Manual (copiar y pegar)

1. Clona el repo:

```bash
git clone https://github.com/sondosclick/aws-bash-toolbox
```

2. Edita tu `~/.bashrc` y añade al final:

```bash
source "$HOME/aws-bash-toolbox/awsctx.sh"
```

> Ajusta el path si clonaste en otra ruta.

3. Recarga:

```bash
source ~/.bashrc
```

---

## 4) Uso rápido

### Ver contexto

```bash
awsctx
```

### Cambiar profile (TAB)

```bash
awsp corp-uat-readonly
```

### Cambiar región (TAB)

```bash
awsr eu-west-3
```

### Selector interactivo profile@region

```bash
awsctxf
```

### Listar instancias EC2

```bash
ec2ls
```

### Conectar por SSM

Por instance-id:

```bash
ssm i-0123456789abcdef0
```

Por tag Name:

```bash
ssm -n api-01
```

Selector interactivo:

```bash
ssmfzf
```

---

## FAQ

### “Error loading SSO Token: Token for <start_url> does not exist”

Solución:

```bash
rm -rf ~/.aws/sso/cache/*
aws sso login --sso-session corp-sso
```

Verifica que tus perfiles usan `sso_session = corp-sso`.

---

### `Cannot perform start session: EOF`

Suele ser proxy/VPN corporativo. El toolbox ejecuta SSM ignorando proxy solo en SSM, pero si sigue:

* prueba sin VPN / otra red (si puedes)
* revisa proxy:

```bash
env | grep -i proxy
```

---

### `session-manager-plugin: command not found`

Instala:

```bash
sudo apt update
sudo apt install -y session-manager-plugin
```

---

### No aparecen instancias en `ssmfzf`

Revisa SSM Agent / permisos / conectividad. Chequeo:

```bash
aws ssm describe-instance-information \
  --profile <profile> --region <region> \
  --query 'InstanceInformationList[].{Id:InstanceId,Status:PingStatus,Agent:AgentVersion}' \
  --output table
```

---

## Archivos del repo

* `awsctx.sh` → funciones Bash (toolbox)
* `install.sh` → instalador (modifica `~/.bashrc` añadiendo `source ...`)
* `README.md` → documentación
