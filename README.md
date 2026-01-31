# aws-bash-toolbox (AWS CLI + SSO + SSM) 🧰

Status: **alpha** (breaking changes are allowed).

A **Bash** toolkit that gives you a `kubectx/kubens`-style workflow for AWS:

- Active context: persistent `AWS_PROFILE` + `AWS_REGION`
- Fast switching: `abt change ...` / `abt select context` (with `fzf`)
- EC2 listing without the console: `abt list ec2`
- SSM Session Manager connect: `abt connect ssm` / `abt select ssm`
- Corporate VPN/proxy workaround: SSM ignores proxy only during sessions
- Utilities: `abt list profiles/regions`, `abt show identity`, `abt test doctor`, `abt sso login`

This repo includes:
- `abt.sh` -> all Bash functions (the toolbox)
- `install.sh` -> installer (copies `abt.sh` to `~/.abt` and sources it from `~/.bashrc`)

---

## Requirements

- Linux (tested on Ubuntu 24.04)
- Bash
- AWS CLI v2
- IAM Identity Center (SSO) access

Install dependencies:

```bash
sudo apt update
sudo apt install -y fzf session-manager-plugin
```

Verify:

```bash
aws --version         # should be aws-cli/2.x
session-manager-plugin
```

---

## Profile naming convention (recommended)

We use:

**`corp-<env>-<role>`**

Examples:

* `corp-dev-readonly`
* `corp-uat-admin`
* `corp-pro-support`

Where:

* `<env>`: target environment (e.g., `dev`, `uat`, `pro`)
* `<role>`: permission set / role in IAM Identity Center (e.g., `admin`, `readonly`, `support`)

> If your team uses other names (`sandbox`, `np`, `prod`, etc.), adjust as needed.
> The important part is consistency.

---

## 1) Configure AWS SSO (profiles)

This toolbox assumes AWS SSO profiles in `~/.aws/config`.

### 1.1 Create/validate the SSO session

In `~/.aws/config`:

```ini
[sso-session corp-sso]
sso_start_url = https://<YOUR_START_URL>/start
sso_region = eu-central-1
sso_registration_scopes = sso:account:access
```

Important: use the Start URL **without** `/#/` to avoid token/cache issues.

### 1.2 Create profiles per account and role (permission set)

Full examples:

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

Note: for SSO the correct pattern is `sso_session + sso_account_id + sso_role_name`.
Avoid `source_profile + role_arn` unless your org explicitly requires classic AssumeRole.

---

## 2) SSO login

If you changed profiles or saw errors:

```bash
rm -rf ~/.aws/sso/cache/*
```

Login:

```bash
aws sso login --sso-session corp-sso
```

Verify:

```bash
aws sts get-caller-identity --profile corp-dev-admin --region eu-west-3
```

---

## 3) Install the toolbox

### Method A) Automated install (recommended)

```bash
git clone https://github.com/sondosclick/aws-bash-toolbox
cd aws-bash-toolbox
./install.sh
source ~/.bashrc
```

What `install.sh` does:

* copies `abt.sh` to `~/.abt/abt.sh`
* adds a line to `~/.bashrc`:

```bash
source "$HOME/.abt/abt.sh"
```

It does not overwrite your bashrc and is safe to run multiple times.

### Method B) Manual (copy/paste)

1. Clone the repo:

```bash
git clone https://github.com/sondosclick/aws-bash-toolbox
```

2. Copy `abt.sh` to `~/.abt`:

```bash
mkdir -p "$HOME/.abt"
cp abt.sh "$HOME/.abt/abt.sh"
```

3. Edit your `~/.bashrc` and add at the end:

```bash
source "$HOME/.abt/abt.sh"
```

4. Reload:

```bash
source ~/.bashrc
```

---

## 4) Optional configuration (abt)

The toolbox can read an optional file: `~/.abt/abt.env` (shell format).

Create a template:

```bash
abt config init
```

Force overwrite:

```bash
abt config init --force
```

Available variables (example):

```bash
ABT_DEFAULT_PROFILE="corp-base"
ABT_DEFAULT_REGION="eu-central-1"
ABT_REGIONS="eu-central-1 eu-west-1 eu-west-3 us-east-1 us-west-2"
ABT_COLOR=1
```

- `ABT_DEFAULT_*`: used when no persisted context exists.
- `ABT_REGIONS`: space-separated list used by selectors.
- `ABT_COLOR=0`: disables colored output.

Show current config:

```bash
abt show config
```

---

## 5) Quick usage

Format: `abt <verb> <object>`

```bash
abt show context
abt show profile
abt show region
abt show identity
abt show version
abt export context
abt list profiles
abt list regions
abt change profile corp-uat-readonly
abt change region eu-west-3
abt change context corp-uat-readonly eu-west-3
abt select context
abt select profile
abt select region
abt list ec2
abt connect ssm i-0123456789abcdef0
abt connect ssm -n api-01
abt select ssm
abt sso login
abt test sts
abt test sts eu-west-3 eu-central-1
abt test doctor
abt config init
abt show config
```

Tip: `abt export context` is handy for scripts:

```bash
source <(abt export context)
```

---

## FAQ

### "Error loading SSO Token: Token for <start_url> does not exist"

Fix:

```bash
rm -rf ~/.aws/sso/cache/*
aws sso login --sso-session corp-sso
```

Verify your profiles use `sso_session = corp-sso`.

---

### `Cannot perform start session: EOF`

Likely corporate proxy/VPN. This toolbox ignores proxy only for SSM, but if it still fails:

* try without VPN / another network (if possible)
* inspect proxy env:

```bash
env | grep -i proxy
```

---

### `session-manager-plugin: command not found`

Install:

```bash
sudo apt update
sudo apt install -y session-manager-plugin
```

---

### No instances show up in `abt select ssm`

Check SSM Agent / permissions / connectivity:

```bash
aws ssm describe-instance-information \
  --profile <profile> --region <region> \
  --query 'InstanceInformationList[].{Id:InstanceId,Status:PingStatus,Agent:AgentVersion}' \
  --output table
```

---

## Repo files

* `abt.sh` -> Bash functions (toolbox)
* `install.sh` -> installer (adds `source ...` to `~/.bashrc`)
* `README.md` -> documentation
