# Night shift deploy (box-one)

1. Create user `nightly` on box-one.
2. As `nightly`: install `mise`, then `mise use -g semgrep trivy jq node@24`.
3. Install opencode: `curl -fsSL https://opencode.ai/install | bash`; `opencode auth login`
   with the **dedicated** opencode go account (not a personal one).
4. Add one read/write deploy key per repo under `~/.ssh` with a `Host` alias each.
5. Clone `campanha-dev-standards` to `~/campanha-dev-standards` and each app to
   `~/repos/<name>`.
6. Write `/etc/campanha/repos`: one absolute checkout path per line, `#` comments allowed.
7. Install the unit and timer:
   `cp deploy/nightly/nightly.{service,timer} /etc/systemd/system/ && systemctl enable --now nightly.timer`
8. Check with `systemctl list-timers nightly.timer` and `journalctl -u nightly`.

Monthly: confirm the DeepSeek row on https://opencode.ai/docs/go/ still says
0 days / not used, then commit today's date to `docs/dev/reviews/.zdr-confirmed`
in each repo.

lefthook is not installed on the server checkouts, so the nightly push runs no hooks.
