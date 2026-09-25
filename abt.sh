#!/usr/bin/env bash
# ============================================================
# AWS Bash Toolbox - Context + EC2 + SSM helpers
# Dual-shell: works when sourced from bash or zsh
# ============================================================

# ----------------------------
# Shell detection
# ----------------------------
# This file is meant to be *sourced* by an interactive shell, so the shell that
# interprets it (bash or zsh) is what matters, not the shebang above. Detect it
# once at load time and branch on _ABT_SHELL wherever the syntax diverges.
if [ -n "${ZSH_VERSION:-}" ]; then
  _ABT_SHELL="zsh"
elif [ -n "${BASH_VERSION:-}" ]; then
  _ABT_SHELL="bash"
else
  _ABT_SHELL="posix"
fi

# Absolute path to this script, resolved per shell.
if [ "$_ABT_SHELL" = "zsh" ]; then
  # In zsh, ${(%):-%x} expands to the path of the current script/source.
  # shellcheck disable=SC2296  # zsh-only parameter expansion; only runs under zsh
  _ABT_SOURCE="${(%):-%x}"
else
  _ABT_SOURCE="${BASH_SOURCE[0]:-$0}"
fi

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
    if [ "$_ABT_SHELL" = "zsh" ]; then
      # zsh word-splits scalars only with ${=VAR}; wrap in eval so bash never
      # parses the zsh-only syntax (bash -n would reject it otherwise).
      eval 'regions=(${=ABT_REGIONS})'
    else
      read -r -a regions <<< "$ABT_REGIONS"
    fi
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

# Portable interactive prompt read.
# Usage: _abt_read_prompt <varname> <prompt>
# Reads a line from the user into the named variable, working in both bash
# (read -r -p) and zsh (read "var?prompt").
_abt_read_prompt() {
  local _abt_var="$1"
  local _abt_prompt_text="$2"
  local _abt_reply=""
  if [ "$_ABT_SHELL" = "zsh" ]; then
    # zsh: `read "name?prompt"` prints the prompt and reads into `name`.
    # Read into a fixed local, then assign indirectly to the caller's var.
    eval 'read "_abt_reply?$_abt_prompt_text"'
  else
    # bash: -p prints the prompt, -r preserves backslashes.
    read -r -p "$_abt_prompt_text" _abt_reply
  fi
  # Indirect assignment to the caller-named variable, valid in bash and zsh.
  eval "$_abt_var=\$_abt_reply"
}

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
    _abt_read_prompt port "Remote port: "
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
    _abt_read_prompt remote_host "Remote host (default $suggested_host): "
    if [ -z "$remote_host" ]; then
      remote_host="$suggested_host"
    fi
  else
    _abt_read_prompt remote_host "Remote host: "
  fi
  [ -z "$remote_host" ] && { echo "Remote host required"; return 1; }

  remote_port="$(_abt_select_db_port)" || return 1
  _abt_read_prompt local_port "Local port (default $remote_port): "
  _abt_ssm_port_forward "$id" "$remote_host" "$remote_port" "$local_port"
}

# ----------------------------
# Completion (bash + zsh)
# ----------------------------
# Shared word lists so the bash and zsh completers stay in sync.

# Level 1: the verbs.
_abt_comp_verbs() {
  echo "show change list connect select test sso export config help"
}

# Level 2: objects valid for a given verb. Echoes nothing for unknown verbs.
_abt_comp_objects() {
  case "$1" in
    show)    echo "context profile region identity version config" ;;
    select)  echo "context profile region ssm forward" ;;
    change)  echo "profile region context" ;;
    list)    echo "ec2 profiles regions" ;;
    test)    echo "sts doctor" ;;
    connect) echo "ssm forward" ;;
    sso)     echo "login" ;;
    export)  echo "context" ;;
    config)  echo "init show" ;;
    *)       echo "" ;;
  esac
}

# Level 3/4: argument suggestions given verb, object and the argument index
# (3 = first arg after the object, 4 = second arg). Echoes nothing when there
# is nothing sensible to suggest.
_abt_comp_args() {
  local verb="$1" obj="$2" pos="$3"
  case "$verb:$obj" in
    change:profile) [ "$pos" -eq 3 ] && _abt_profiles_list ;;
    change:region)  [ "$pos" -eq 3 ] && _abt_regions_list ;;
    change:context)
      if [ "$pos" -eq 3 ]; then _abt_profiles_list
      elif [ "$pos" -eq 4 ]; then _abt_regions_list
      fi
      ;;
    select:profile) [ "$pos" -eq 3 ] && _abt_profiles_list ;;
    select:region)  [ "$pos" -eq 3 ] && _abt_regions_list ;;
    sso:login)      [ "$pos" -eq 3 ] && _abt_sso_sessions_list ;;
    config:init)    [ "$pos" -eq 3 ] && echo "--force" ;;
  esac
}

if [ "$_ABT_SHELL" = "zsh" ]; then
  # ---- zsh native completion ----
  # $words is the full command line (1-indexed), $CURRENT the cursor position.
  _abt() {
    local verb obj pos
    # words and CURRENT are zsh completion specials, set by the completion
    # system; they are not assigned here.
    # shellcheck disable=SC2154,SC2153
    verb="${words[2]}"
    # shellcheck disable=SC2154
    obj="${words[3]}"
    # shellcheck disable=SC2153
    pos=$((CURRENT - 1))

    if [ "$CURRENT" -eq 2 ]; then
      # shellcheck disable=SC2046
      compadd -- $(_abt_comp_verbs)
      return 0
    fi

    if [ "$CURRENT" -eq 3 ]; then
      # shellcheck disable=SC2046
      compadd -- $(_abt_comp_objects "$verb")
      return 0
    fi

    # CURRENT >= 4 -> argument positions (pos 3 for CURRENT 4, etc.)
    local suggestions
    suggestions="$(_abt_comp_args "$verb" "$obj" "$pos")"
    if [ -n "$suggestions" ]; then
      # shellcheck disable=SC2086
      compadd -- ${=suggestions}
    fi
    return 0
  }

  # Register only if the zsh completion system is initialized (compinit loaded).
  if whence compdef >/dev/null 2>&1; then
    compdef _abt abt
  fi
else
  # ---- bash native completion ----
  _abt_complete_words() {
    local words="$1"
    local cur="$2"
    local w
    COMPREPLY=()
    # Read-loop instead of mapfile so this works on Bash 3.2 (macOS default),
    # which predates mapfile (Bash 4.0+).
    while IFS= read -r w; do
      [ -n "$w" ] && COMPREPLY+=("$w")
    done < <(compgen -W "$words" -- "$cur")
  }

  _abt_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local verb="${COMP_WORDS[1]}"
    local obj="${COMP_WORDS[2]}"

    if [ "$COMP_CWORD" -eq 1 ]; then
      _abt_complete_words "$(_abt_comp_verbs)" "$cur"
      return 0
    fi

    if [ "$COMP_CWORD" -eq 2 ]; then
      local objs
      objs="$(_abt_comp_objects "$verb")"
      if [ -n "$objs" ]; then
        _abt_complete_words "$objs" "$cur"
      else
        COMPREPLY=()
      fi
      return 0
    fi

    # COMP_CWORD >= 3 -> argument positions.
    local suggestions
    suggestions="$(_abt_comp_args "$verb" "$obj" "$COMP_CWORD")"
    if [ -n "$suggestions" ]; then
      _abt_complete_words "$suggestions" "$cur"
    else
      COMPREPLY=()
    fi
    return 0
  }
  complete -F _abt_complete abt
fi

# ----------------------------
# Prompt (optional)
# ----------------------------

_abt_prompt() {
  printf '[aws:%s@%s]' "${AWS_PROFILE}" "${AWS_REGION}"
}

if [ "$_ABT_SHELL" = "zsh" ]; then
  # zsh: PROMPT_SUBST re-evaluates $(...) on every prompt render. Inject once.
  # Guard on the _abt_prompt call itself (the "aws:" text only appears at
  # render time, so guarding on it would double-inject on re-source).
  case "${PROMPT:-}" in
    *"_abt_prompt"*) : ;;  # already injected
    *)
      setopt PROMPT_SUBST
      # Single quotes are intentional: PROMPT_SUBST re-evaluates $(_abt_prompt)
      # on every prompt render.
      # shellcheck disable=SC2016
      PROMPT='$(_abt_prompt) '"${PROMPT:-}"
      ;;
  esac
elif [ "$_ABT_SHELL" = "bash" ]; then
  case "${PS1:-}" in
    *"_abt_prompt"*) : ;;  # already injected
    *)
      PS1='$( _abt_prompt ) '"${PS1:-}"
      ;;
  esac
fi

# ----------------------------
# Init
# ----------------------------

_abt_ctx_load
