# Contributing

Thanks for taking the time to contribute.

## Quick start

1. Fork the repo and create a topic branch from `main`.
2. Keep PRs focused and small when possible.
3. Update docs if you change behavior or CLI usage.

## Development

Recommended checks before opening a PR:

```bash
bash -n abt.sh install.sh
shellcheck abt.sh install.sh
```

Optional local checks:

```bash
# requires AWS CLI and valid credentials
source ./abt.sh
abt test doctor
abt test sts
```

Notes:
- `abt test sts` requires valid AWS credentials and will call AWS.
- Keep dependencies to common distro packages (e.g., `fzf`, `jq`).

## Style

- Prefer portable Bash.
- Avoid adding new required dependencies unless necessary.
- If you add new commands, update `README.md` and completion logic.
