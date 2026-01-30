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
awsrl() {
  cat <<'EOF'
eu-central-1
eu-west-1
eu-west-3
us-east-1
us-west-2
EOF
}

# ----------------------------
# Context persistence
# ----------------------------

awsctxload() {
  if [ -f "$AWSCTX_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AWSCTX_FILE"
  fi
}

awsctxsave() {
  mkdir -p "$(dirname "$AWSCTX_FILE")"
  {
    echo "export AWS_PROFILE='${AWS_PROFILE}'"
    echo "export AWS_REGION='${AWS_REGION}'"
  } > "$AWSCTX_FILE"
}

awsctx() {
  echo "AWS_PROFILE=$AWS_PROFILE  AWS_REGION=$AWS_REGION"
}

# ----------------------------
# Profile / region switching
# ----------------------------

# List profiles from ~/.aws/config
awspl() {
  awk '/^\[profile /{gsub(/^\[profile /,""); gsub(/\]$/,""); print}' ~/.aws/config | sort
}

# Switch profile
awsp() {
  [ -z "$1" ] && { echo "Usage: awsp <profile>"; return 1; }
  export AWS_PROFILE="$1"
  awsctxsave
  awsctx
}

# Switch region
awsr() {
  [ -z "$1" ] && { echo "Usage: awsr <region>"; return 1; }
  export AWS_REGION="$1"
  awsctxsave
  awsctx
}

# ----------------------------
# Interactive context selector (fzf)
# ----------------------------

awsctxf() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local profiles regions current choice prof region
  current="${AWS_PROFILE}@${AWS_REGION}"
  profiles="$(awspl)"
  regions="${AWSCTXF_REGIONS:-$(awsrl)}"

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
  awsctxsave
  awsctx
}

# ----------------------------
# AWS command wrapper
# ----------------------------

awscmd() {
  aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
}

# ----------------------------
# EC2 helpers
# ----------------------------

ec2ls() {
  awscmd ec2 describe-instances \
    --query 'Reservations[].Instances[].{Name: Tags[?Key==`Name`]|[0].Value, InstanceId: InstanceId, PrivateIP: PrivateIpAddress, State: State.Name}' \
    --output table
}

# ----------------------------
# SSM helpers
# ----------------------------

# Usage:
#   ssm i-0123...
#   ssm -n instance-name
ssm() {
  local target=""
  if [ "$1" = "-n" ]; then
    [ -z "$2" ] && { echo "Usage: ssm -n <NameTag>"; return 1; }
    target=$(awscmd ec2 describe-instances \
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
ssmfzf() {
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed"; return 1; }

  local id
  id=$(awscmd ec2 describe-instances \
      --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`]|[0].Value, PrivateIpAddress, State.Name]' \
      --output text \
    | awk '$4=="running"{print $0}' \
    | fzf --prompt="SSM (${AWS_PROFILE}@${AWS_REGION})> " \
    | awk '{print $1}')

  [ -z "$id" ] && return 0
  ssm "$id"
}

# ----------------------------
# Bash completion
# ----------------------------

_aws_profiles_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "$(awspl)" -- "$cur"))
}
complete -F _aws_profiles_complete awsp

_aws_regions_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=($(compgen -W "$(awsrl)" -- "$cur"))
}
complete -F _aws_regions_complete awsr

complete -o default awsctxf

# ----------------------------
# Prompt (optional)
# ----------------------------

aws_prompt() {
  echo -n "[aws:${AWS_PROFILE}@${AWS_REGION}]"
}

if [[ "$PS1" != *"aws:"* ]]; then
  PS1='$(aws_prompt) '"$PS1"
fi

# ----------------------------
# Init
# ----------------------------

awsctxload
