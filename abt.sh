#!/usr/bin/env bash
# ============================================================
# AWS Bash Toolbox - Context + EC2 + SSM helpers
# Bash / Ubuntu
# ============================================================

# ----------------------------
# Configuration
# ----------------------------

ABT_VERSION="0.4.0-alpha"
ABT_CONFIG_FILE="${HOME}/.abt/abt.env"
AWSCTX_FILE="${HOME}/.aws/awsctx.env"

_abt_config_load() {
  if [ -f "$ABT_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ABT_CONFIG_FILE"
  fi
}

_abt_config_load

# Defaults if no persisted context exists
: "${ABT_DEFAULT_PROFILE:=corp-base}"
: "${ABT_DEFAULT_REGION:=eu-central-1}"
: "${AWS_PROFILE:=$ABT_DEFAULT_PROFILE}"
: "${AWS_REGION:=$ABT_DEFAULT_REGION}"

# Regions shown in selectors (edit to taste)
_abt_regions_list() {
  if [ -n "${ABT_REGIONS:-}" ]; then
    local -a regions
    read -r -a regions <<< "$ABT_REGIONS"
    printf "%s\n" "${regions[@]}"
    return 0
  fi
  cat <<'EOF'
eu-central-1
eu-west-1
eu-west-3
us-east-1
us-west-2
EOF
}

_abt_config_init() {
  local force=0
  if [ "${1:-}" = "--force" ]; then
    force=1
  fi

  mkdir -p "$(dirname "$ABT_CONFIG_FILE")"
  if [ -f "$ABT_CONFIG_FILE" ] && [ "$force" -eq 0 ]; then
    echo "Config already exists: $ABT_CONFIG_FILE"
    echo "Use: abt config init --force"
    return 1
  fi

  cat > "$ABT_CONFIG_FILE" <<'EOF'
# abt configuration (shell)
# ABT_DEFAULT_PROFILE="corp-base"
# ABT_DEFAULT_REGION="eu-central-1"
# ABT_REGIONS="eu-central-1 eu-west-1 eu-west-3 us-east-1 us-west-2"
# ABT_COLOR=1
EOF
  echo "Wrote $ABT_CONFIG_FILE"
}

# ----------------------------
# Context persistence (internal)
# ----------------------------

_abt_ctx_load() {
  if [ -f "$AWSCTX_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AWSCTX_FILE"
  fi
}

_abt_ctx_save() {
  mkdir -p "$(dirname "$AWSCTX_FILE")"
  {
    echo "export AWS_PROFILE='${AWS_PROFILE}'"
    echo "export AWS_REGION='${AWS_REGION}'"
  } > "$AWSCTX_FILE"
}

_abt_ctx_show() {
  echo "AWS_PROFILE=$AWS_PROFILE  AWS_REGION=$AWS_REGION"
}

# ----------------------------
# Profile / region switching (internal)
# ----------------------------

# List profiles from ~/.aws/config
_abt_profiles_list() {
  [ -f ~/.aws/config ] || return 0
  awk '/^\[profile /{gsub(/^\[profile /,""); gsub(/\]$/,""); print}' ~/.aws/config | sort
}

_abt_sso_sessions_list() {
  [ -f ~/.aws/config ] || return 0
  awk '/^\[sso-session /{gsub(/^\[sso-session /,""); gsub(/\]$/,""); print}' ~/.aws/config | sort
}

# Switch profile
_abt_change_profile() {
  [ -z "$1" ] && { echo "Usage: abt change profile <profile>"; return 1; }
  export AWS_PROFILE="$1"
  _abt_ctx_save
  _abt_ctx_show
}

# Switch region
_abt_change_region() {
  [ -z "$1" ] && { echo "Usage: abt change region <region>"; return 1; }
  export AWS_REGION="$1"
  _abt_ctx_save
  _abt_ctx_show
}

# Switch context
_abt_change_context() {
  [ -z "$1" ] && { echo "Usage: abt change context <profile> [region]"; return 1; }
  export AWS_PROFILE="$1"
  if [ -n "${2:-}" ]; then
    export AWS_REGION="$2"
  fi
  _abt_ctx_save
  _abt_ctx_show
}

# ----------------------------
# Interactive context selector (fzf) (internal)
# ----------------------------

_abt_ctx_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local profiles regions current choice prof region
  current="${AWS_PROFILE}@${AWS_REGION}"
  profiles="$(_abt_profiles_list)"
  regions="$(_abt_regions_list)"

  if [ -z "$profiles" ]; then
    echo "No profiles found in ~/.aws/config"
    return 1
  fi

  choice=$( {
      while read -r prof; do
        while read -r region; do
          printf "%s@%s\n" "$prof" "$region"
        done <<< "$regions"
      done <<< "$profiles"
    } | awk -v cur="$current" '{print ($0==cur ? "★ " $0 : "  " $0)}' \
      | fzf --prompt="AWS Context > " --reverse --height=20
  )

  [ -z "$choice" ] && return 0

  choice="${choice#★ }"
  choice="${choice#  }"
  prof="${choice%@*}"
  region="${choice#*@}"

  export AWS_PROFILE="$prof"
  export AWS_REGION="$region"
  _abt_ctx_save
  _abt_ctx_show
}

# Select profile only (fzf)
_abt_profile_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local profiles choice
  profiles="$(_abt_profiles_list)"
  if [ -z "$profiles" ]; then
    echo "No profiles found in ~/.aws/config"
    return 1
  fi

  choice=$(printf "%s\n" "$profiles" | fzf --prompt="AWS Profile > " --reverse --height=20)
  [ -z "$choice" ] && return 0

  export AWS_PROFILE="$choice"
  _abt_ctx_save
  _abt_ctx_show
}

# Select region only (fzf)
_abt_region_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local regions choice
  regions="$(_abt_regions_list)"
  if [ -z "$regions" ]; then
    echo "No regions configured"
    return 1
  fi

  choice=$(printf "%s\n" "$regions" | fzf --prompt="AWS Region > " --reverse --height=20)
  [ -z "$choice" ] && return 0

  export AWS_REGION="$choice"
  _abt_ctx_save
  _abt_ctx_show
}

# ----------------------------
# AWS command wrapper (internal)
# ----------------------------

_abt_cmd() {
  aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

# ----------------------------
# Show / export helpers (internal)
# ----------------------------

_abt_show_profile() {
  echo "$AWS_PROFILE"
}

_abt_show_region() {
  echo "$AWS_REGION"
}

_abt_show_identity() {
  _abt_cmd sts get-caller-identity
}

_abt_show_version() {
  echo "abt $ABT_VERSION"
}

_abt_show_config() {
  if [ -f "$ABT_CONFIG_FILE" ]; then
    cat "$ABT_CONFIG_FILE"
  else
    echo "Config not found: $ABT_CONFIG_FILE"
    return 1
  fi
}

_abt_export_context() {
  echo "export AWS_PROFILE='${AWS_PROFILE}'"
  echo "export AWS_REGION='${AWS_REGION}'"
}

_abt_sso_login() {
  local session="${1:-}"
  if [ -n "$session" ]; then
    aws sso login --sso-session "$session"
  else
    aws sso login --profile "$AWS_PROFILE"
  fi
}

# ----------------------------
# Unified command (abt)
# ----------------------------

_abt_usage() {
  cat <<'EOF'
Usage:
  abt show context
  abt show profile
  abt show region
  abt show identity
  abt show version
  abt show config
  abt export context
  abt list profiles
  abt list regions
  abt change profile <profile>
  abt change region <region>
  abt change context <profile> [region]
  abt select context
  abt select profile
  abt select region
  abt list ec2
  abt connect ssm <instance-id>
  abt connect ssm -n <NameTag>
  abt connect forward <instance-id> <remote-host> <remote-port> [local-port]
  abt connect forward -n <NameTag> <remote-host> <remote-port> [local-port]
  abt select ssm
  abt select forward
  abt sso login [session]
  abt test sts [region...]
  abt test doctor
  abt config init [--force]
  abt config show
  abt help
EOF
}

abt() {
  local verb="${1:-}"
  local obj="${2:-}"

  if [ -z "$verb" ] || [ "$verb" = "help" ] || [ "$verb" = "-h" ] || [ "$verb" = "--help" ]; then
    _abt_usage
    return 0
  fi

  if [ -z "$obj" ] || [ "$obj" = "help" ]; then
    _abt_usage
    return 1
  fi

  shift 2

  case "${verb}:${obj}" in
    show:context)
      _abt_ctx_show
      ;;
    show:profile)
      _abt_show_profile
      ;;
    show:region)
      _abt_show_region
      ;;
    show:identity)
      _abt_show_identity
      ;;
    show:version)
      _abt_show_version
      ;;
    show:config)
      _abt_show_config
      ;;
    export:context)
      _abt_export_context
      ;;
    list:profiles)
      _abt_profiles_list
      ;;
    list:regions)
      _abt_regions_list
      ;;
    change:profile)
      _abt_change_profile "$@"
      ;;
    change:region)
      _abt_change_region "$@"
      ;;
    change:context)
      _abt_change_context "$@"
      ;;
    select:context)
      _abt_ctx_select
      ;;
    select:profile)
      _abt_profile_select
      ;;
    select:region)
      _abt_region_select
      ;;
    list:ec2)
      _abt_ec2_list
      ;;
    test:sts)
      _abt_test_sts "$@"
      ;;
    test:doctor)
      _abt_doctor
      ;;
    connect:ssm)
      _abt_ssm_connect "$@"
      ;;
    connect:forward)
      _abt_ssm_port_forward "$@"
      ;;
    select:ssm)
      _abt_ssm_select
      ;;
    select:forward)
      _abt_forward_select
      ;;
    sso:login)
      _abt_sso_login "$@"
      ;;
    config:init)
      _abt_config_init "$@"
      ;;
    config:show)
      _abt_show_config
      ;;
    *)
      _abt_usage
      return 1
      ;;
  esac
}

# ----------------------------
# EC2 helpers (internal)
# ----------------------------

_abt_ec2_list() {
  _abt_cmd ec2 describe-instances \
    --query "Reservations[].Instances[].{Name: Tags[?Key==\`Name\`]|[0].Value, InstanceId: InstanceId, PrivateIP: PrivateIpAddress, State: State.Name}" \
    --output table
}

# ----------------------------
# Tests (internal)
# ----------------------------

_abt_color_enabled() {
  [ -t 1 ] && [ "${ABT_COLOR:-1}" != "0" ]
}

_abt_test_sts() {
  local regions profiles fail profile region
  local c_green c_red c_reset

  if _abt_color_enabled; then
    c_green=$'\033[0;32m'
    c_red=$'\033[0;31m'
    c_reset=$'\033[0m'
  else
    c_green=""
    c_red=""
    c_reset=""
  fi

  profiles="$(_abt_profiles_list)"
  if [ -z "$profiles" ]; then
    echo "No profiles found in ~/.aws/config"
    return 1
  fi

  if [ "$#" -gt 0 ]; then
    regions="$*"
  else
    regions="eu-west-3 eu-central-1"
  fi

  fail=0
  printf "%-24s %-16s %-8s\n" "PROFILE" "REGION" "STATUS"
  printf "%-24s %-16s %-8s\n" "------------------------" "----------------" "--------"
  for profile in $profiles; do
    for region in $regions; do
      if aws sts get-caller-identity --profile "$profile" --region "$region" >/dev/null 2>&1; then
        printf "%-24s %-16s %b%-8s%b\n" "$profile" "$region" "$c_green" "OK" "$c_reset"
      else
        printf "%-24s %-16s %b%-8s%b\n" "$profile" "$region" "$c_red" "FAIL" "$c_reset"
        fail=1
      fi
    done
  done

  return "$fail"
}

_abt_doctor_check() {
  local _fail_ref="$1"
  local cmd="$2"
  local label="$3"
  local required="${4:-yes}"

  if command -v "$cmd" >/dev/null 2>&1; then
    printf "OK   %s\n" "$label"
  else
    if [ "$required" = "yes" ]; then
      printf "FAIL %s (missing: %s)\n" "$label" "$cmd"
      eval "$_fail_ref=1"
    else
      printf "WARN %s (missing: %s)\n" "$label" "$cmd"
    fi
  fi
}

_abt_doctor() {
  local fail=0

  _abt_doctor_check fail "aws" "AWS CLI" "yes"
  _abt_doctor_check fail "session-manager-plugin" "SSM Session Manager plugin" "yes"
  _abt_doctor_check fail "fzf" "fzf (optional)" "no"

  if [ -f ~/.aws/config ]; then
    if [ -n "$(_abt_profiles_list)" ]; then
      printf "OK   AWS profiles found\n"
    else
      printf "WARN AWS profiles not found in ~/.aws/config\n"
    fi
  else
    printf "WARN ~/.aws/config not found\n"
  fi

  if [ -f "$ABT_CONFIG_FILE" ]; then
    printf "OK   abt config found (%s)\n" "$ABT_CONFIG_FILE"
  else
    printf "WARN abt config not found (%s)\n" "$ABT_CONFIG_FILE"
  fi

  return "$fail"
}

# ----------------------------
# SSM helpers (internal)
# ----------------------------

_abt_validate_port() {
  local port="$1"
  case "$port" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    return 1
  fi
  return 0
}

_abt_common_db_ports() {
  cat <<'EOF'
postgres (5432)
mysql (3306)
mariadb (3306)
mssql (1433)
oracle (1521)
redis (6379)
mongodb (27017)
opensearch (9200)
EOF
}

_abt_select_db_port() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local selected_port_option port
  selected_port_option=$( { _abt_common_db_ports; echo "custom"; } \
    | fzf --prompt="Remote port > " --reverse --height=20 )

  [ -z "$selected_port_option" ] && return 1

  if [ "$selected_port_option" = "custom" ]; then
    read -r -p "Remote port: " port
  else
    port=$(printf "%s" "$selected_port_option" | awk -F'[()]' '{print $2}')
  fi

  [ -z "$port" ] && { echo "Remote port required"; return 1; }
  if ! _abt_validate_port "$port"; then
    echo "Invalid port: $port (must be 1-65535)"
    return 1
  fi
  echo "$port"
}

_abt_forward_default_host() {
  local instance_id="$1"
  local tags key value

  tags=$(_abt_cmd ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query "Reservations[0].Instances[0].Tags[?Key=='ForwardHost' || Key=='DBHost' || Key=='DbHost' || Key=='DBEndpoint' || Key=='RDSEndpoint' || Key=='RDSHost' || Key=='db_host'].[Key,Value]" \
    --output text 2>/dev/null)

  [ -z "$tags" ] && return 1

  for key in ForwardHost DBHost DbHost DBEndpoint RDSEndpoint RDSHost db_host; do
    value=$(printf "%s\n" "$tags" | awk -v k="$key" '$1==k{print $2; exit}')
    if [ -n "$value" ] && [ "$value" != "None" ]; then
      echo "$value"
      return 0
    fi
  done

  return 1
}

# Usage:
#   abt connect ssm i-0123...
#   abt connect ssm -n instance-name
_abt_ssm_connect() {
  local target=""
  if [ "$1" = "-n" ]; then
    [ -z "$2" ] && { echo "Usage: abt connect ssm -n <NameTag>"; return 1; }
    target=$(_abt_cmd ec2 describe-instances \
      --filters "Name=tag:Name,Values=$2" "Name=instance-state-name,Values=running" \
      --query 'Reservations[0].Instances[0].InstanceId' \
      --output text)
  else
    target="$1"
  fi

  [ -z "$target" ] || [ "$target" = "None" ] && { echo "Instance not found"; return 2; }

  # Bypass proxy ONLY for SSM (corporate VPN fix)
  env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy \
    aws --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    ssm start-session --target "$target"
}

# Usage:
#   abt connect forward i-0123... db.internal 5432 [local-port]
#   abt connect forward -n instance-name db.internal 5432 [local-port]
_abt_ssm_port_forward() {
  local target="" remote_host="" remote_port="" local_port=""

  if [ "$1" = "-n" ]; then
    [ -z "$2" ] && { echo "Usage: abt connect forward -n <NameTag> <remote-host> <remote-port> [local-port]"; return 1; }
    target=$(_abt_cmd ec2 describe-instances \
      --filters "Name=tag:Name,Values=$2" "Name=instance-state-name,Values=running" \
      --query 'Reservations[0].Instances[0].InstanceId' \
      --output text)
    shift 2
  else
    target="$1"
    shift 1
  fi

  remote_host="${1:-}"
  remote_port="${2:-}"
  local_port="${3:-}"

  [ -z "$target" ] || [ "$target" = "None" ] && { echo "Instance not found"; return 2; }
  if [ -z "$remote_host" ] || [ -z "$remote_port" ]; then
    echo "Usage: abt connect forward <instance-id> <remote-host> <remote-port> [local-port]"
    return 1
  fi

  if ! _abt_validate_port "$remote_port"; then
    echo "Invalid remote port: $remote_port (must be 1-65535)"
    return 1
  fi

  if [ -z "$local_port" ]; then
    local_port="$remote_port"
  elif ! _abt_validate_port "$local_port"; then
    echo "Invalid local port: $local_port (must be 1-65535)"
    return 1
  fi

  # Bypass proxy ONLY for SSM (corporate VPN fix)
  env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy \
    aws --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    ssm start-session --target "$target" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "host=$remote_host,portNumber=$remote_port,localPortNumber=$local_port"
}

# Interactive SSM selector
_abt_ssm_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local id
  id=$(_abt_cmd ec2 describe-instances \
      --query "Reservations[].Instances[].[InstanceId, Tags[?Key==\`Name\`]|[0].Value, PrivateIpAddress, State.Name]" \
      --output text \
    | awk '$4=="running"{print $0}' \
    | fzf --prompt="SSM (${AWS_PROFILE}@${AWS_REGION})> " \
    | awk '{print $1}')

  [ -z "$id" ] && return 0
  _abt_ssm_connect "$id"
}

_abt_forward_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local id remote_host remote_port local_port suggested_host
  id=$(_abt_cmd ec2 describe-instances \
      --query "Reservations[].Instances[].[InstanceId, Tags[?Key==\`Name\`]|[0].Value, PrivateIpAddress, State.Name]" \
      --output text \
    | awk '$4=="running"{print $0}' \
    | fzf --prompt="Forward (${AWS_PROFILE}@${AWS_REGION})> " \
    | awk '{print $1}')

  [ -z "$id" ] && return 0

  suggested_host="$(_abt_forward_default_host "$id")"
  if [ -n "$suggested_host" ]; then
    read -r -p "Remote host (default $suggested_host): " remote_host
    if [ -z "$remote_host" ]; then
      remote_host="$suggested_host"
    fi
  else
    read -r -p "Remote host: " remote_host
  fi
  [ -z "$remote_host" ] && { echo "Remote host required"; return 1; }

  remote_port="$(_abt_select_db_port)" || return 1
  read -r -p "Local port (default $remote_port): " local_port
  _abt_ssm_port_forward "$id" "$remote_host" "$remote_port" "$local_port"
}

# ----------------------------
# Bash completion
# ----------------------------

_abt_complete_words() {
  local words="$1"
  local cur="$2"
  mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
}

_abt_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local verb="${COMP_WORDS[1]}"
  local obj="${COMP_WORDS[2]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    _abt_complete_words "show change list connect select test sso export config help" "$cur"
    return 0
  fi

  if [ "$COMP_CWORD" -eq 2 ]; then
    case "$verb" in
      show)
        _abt_complete_words "context profile region identity version config" "$cur"
        ;;
    select)
        _abt_complete_words "context profile region ssm forward" "$cur"
        ;;
      change)
        _abt_complete_words "profile region context" "$cur"
        ;;
      list)
        _abt_complete_words "ec2 profiles regions" "$cur"
        ;;
      test)
        _abt_complete_words "sts doctor" "$cur"
        ;;
      connect)
        _abt_complete_words "ssm forward" "$cur"
        ;;
      sso)
        _abt_complete_words "login" "$cur"
        ;;
      export)
        _abt_complete_words "context" "$cur"
        ;;
      config)
        _abt_complete_words "init show" "$cur"
        ;;
      *)
        COMPREPLY=()
        ;;
    esac
    return 0
  fi

  if [ "$verb" = "change" ] && [ "$obj" = "profile" ] && [ "$COMP_CWORD" -eq 3 ]; then
    _abt_complete_words "$(_abt_profiles_list)" "$cur"
    return 0
  fi

  if [ "$verb" = "change" ] && [ "$obj" = "region" ] && [ "$COMP_CWORD" -eq 3 ]; then
    _abt_complete_words "$(_abt_regions_list)" "$cur"
    return 0
  fi

  if [ "$verb" = "change" ] && [ "$obj" = "context" ]; then
    if [ "$COMP_CWORD" -eq 3 ]; then
      _abt_complete_words "$(_abt_profiles_list)" "$cur"
      return 0
    fi
    if [ "$COMP_CWORD" -eq 4 ]; then
      _abt_complete_words "$(_abt_regions_list)" "$cur"
      return 0
    fi
  fi

  if [ "$verb" = "select" ] && [ "$obj" = "profile" ] && [ "$COMP_CWORD" -eq 3 ]; then
    _abt_complete_words "$(_abt_profiles_list)" "$cur"
    return 0
  fi

  if [ "$verb" = "select" ] && [ "$obj" = "region" ] && [ "$COMP_CWORD" -eq 3 ]; then
    _abt_complete_words "$(_abt_regions_list)" "$cur"
    return 0
  fi

  if [ "$verb" = "sso" ] && [ "$obj" = "login" ] && [ "$COMP_CWORD" -eq 3 ]; then
    _abt_complete_words "$(_abt_sso_sessions_list)" "$cur"
    return 0
  fi

  if [ "$verb" = "config" ] && [ "$obj" = "init" ] && [ "$COMP_CWORD" -eq 3 ]; then
    _abt_complete_words "--force" "$cur"
    return 0
  fi
}
complete -F _abt_complete abt

# ----------------------------
# Prompt (optional)
# ----------------------------

_abt_prompt() {
  echo -n "[aws:${AWS_PROFILE}@${AWS_REGION}]"
}

if [[ "$PS1" != *"aws:"* ]]; then
  PS1='$( _abt_prompt ) '"$PS1"
fi

# ----------------------------
# Init
# ----------------------------

_abt_ctx_load
