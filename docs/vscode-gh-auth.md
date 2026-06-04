# VS Code Source Control with GitHub CLI

If VS Code asks for a password for `ayo@github.com`, Git is using an old credential helper or an old remote identity. Use GitHub CLI as the HTTPS credential helper:

```bash
gh auth setup-git
git remote set-url origin https://github.com/countervolts/Volta.git
git config --global credential.username countervolts
git config --global --replace-all credential.https://github.com.helper "!/usr/bin/gh auth git-credential"
```

If your `gh` binary lives somewhere else, use `command -v gh` and replace `/usr/bin/gh` with that path. The important bit is `--replace-all`; it clears duplicate helper values instead of failing with `cannot overwrite multiple values`.

If you previously used Git's plaintext `store` helper, remove any old GitHub entry too:

```bash
git credential reject <<EOF
protocol=https
host=github.com
username=countervolts
EOF
```

Then commit from VS Code Source Control:

1. Stage files with `+`.
2. Type a commit message.
3. Press `Commit`.
4. Press `Sync Changes` or `Push`.

Check it:

```bash
git remote -v
gh auth status
git credential fill <<EOF
protocol=https
host=github.com
EOF
```

`git credential fill` should return username `countervolts` and a token-like password from `gh`.
