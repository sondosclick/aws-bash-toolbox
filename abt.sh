#!/usr/bin/env bash
# ============================================================
# AWS Bash Toolbox - Context + EC2 + SSM helpers
# Bash / Ubuntu
# ============================================================

# ----------------------------
# Configuration
# ----------------------------

AWSCTX_FILE="${HOME}/.aws/awsctx.env"

# Defaults if no persisted context exists
: "${AWS_PROFILE:=corp-base}"
: "${AWS_REGION:=eu-central-1}"

# Regions shown in selectors (edit to taste)
_abt_regions_list() {
  cat <<'EOF'
eu-central-1
eu-west-1
eu-west-3
us-east-1
us-west-2
EOF
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
  awk '/^\[profile /{gsub(/^\[profile /,""); gsub(/\]$/,""); print}' ~/.aws/config | sort
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

# ----------------------------
# Interactive context selector (fzf) (internal)
# ----------------------------

_abt_ctx_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local profiles regions current choice prof region
  current="${AWS_PROFILE}@${AWS_REGION}"
  profiles="$(_abt_profiles_list)"
  regions="${AWSCTXF_REGIONS:-$(_abt_regions_list)}"

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

# ----------------------------
# AWS command wrapper (internal)
# ----------------------------

_abt_cmd() {
  aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

# ----------------------------
# Unified command (abt)
# ----------------------------

_abt_usage() {
  cat <<'EOF'
Usage:
  abt show context
  abt change profile <profile>
  abt change region <region>
  abt change context <profile> <region>
  abt select context
  abt list ec2
  abt connect ssm <instance-id>
  abt connect ssm -n <NameTag>
  abt select ssm
  abt test sts [region...]
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
    change:profile)
      _abt_change_profile "$@"
      ;;
    change:region)
      _abt_change_region "$@"
      ;;
    change:context)
      [ -z "${1:-}" ] || [ -z "${2:-}" ] && { echo "Usage: abt change context <profile> <region>"; return 1; }
      export AWS_PROFILE="$1"
      export AWS_REGION="$2"
      _abt_ctx_save
      _abt_ctx_show
      ;;
    select:context)
      _abt_ctx_select
      ;;
    list:ec2)
      _abt_ec2_list
      ;;
    test:sts)
      _abt_test_sts "$@"
      ;;
    connect:ssm)
      _abt_ssm_connect "$@"
      ;;
    select:ssm)
      _abt_ssm_select
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
    --query 'Reservations[].Instances[].{Name: Tags[?Key==`Name`]|[0].Value, InstanceId: InstanceId, PrivateIP: PrivateIpAddress, State: State.Name}' \
    --output table
}

# ----------------------------
# Tests (internal)
# ----------------------------

_abt_test_sts() {
  local regions profiles fail profile region
  local c_green c_red c_reset

  if [ -t 1 ]; then
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

# ----------------------------
# SSM helpers (internal)
# ----------------------------

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

# Interactive SSM selector
_abt_ssm_select() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local id
  id=$(_abt_cmd ec2 describe-instances \
      --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`]|[0].Value, PrivateIpAddress, State.Name]' \
      --output text \
    | awk '$4=="running"{print $0}' \
    | fzf --prompt="SSM (${AWS_PROFILE}@${AWS_REGION})> " \
    | awk '{print $1}')

  [ -z "$id" ] && return 0
  _abt_ssm_connect "$id"
}

# ----------------------------
# Bash completion
# ----------------------------

_abt_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local verb="${COMP_WORDS[1]}"
  local obj="${COMP_WORDS[2]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "show change list connect select test help" -- "$cur"))
    return 0
  fi

  if [ "$COMP_CWORD" -eq 2 ]; then
    case "$verb" in
      show)
        COMPREPLY=($(compgen -W "context" -- "$cur"))
        ;;
      select)
        COMPREPLY=($(compgen -W "context ssm" -- "$cur"))
        ;;
      change)
        COMPREPLY=($(compgen -W "profile region context" -- "$cur"))
        ;;
      list)
        COMPREPLY=($(compgen -W "ec2" -- "$cur"))
        ;;
      test)
        COMPREPLY=($(compgen -W "sts" -- "$cur"))
        ;;
      connect)
        COMPREPLY=($(compgen -W "ssm" -- "$cur"))
        ;;
      *)
        COMPREPLY=()
        ;;
    esac
    return 0
  fi

  if [ "$verb" = "change" ] && [ "$obj" = "profile" ] && [ "$COMP_CWORD" -eq 3 ]; then
    COMPREPLY=($(compgen -W "$(_abt_profiles_list)" -- "$cur"))
    return 0
  fi

  if [ "$verb" = "change" ] && [ "$obj" = "region" ] && [ "$COMP_CWORD" -eq 3 ]; then
    COMPREPLY=($(compgen -W "$(_abt_regions_list)" -- "$cur"))
    return 0
  fi

  if [ "$verb" = "change" ] && [ "$obj" = "context" ]; then
    if [ "$COMP_CWORD" -eq 3 ]; then
      COMPREPLY=($(compgen -W "$(_abt_profiles_list)" -- "$cur"))
      return 0
    fi
    if [ "$COMP_CWORD" -eq 4 ]; then
      COMPREPLY=($(compgen -W "$(_abt_regions_list)" -- "$cur"))
      return 0
    fi
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
