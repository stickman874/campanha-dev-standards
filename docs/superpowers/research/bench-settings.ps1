# Benchmark: same tiny task under the template's full .claude/settings.json vs no sandbox vs slim.
# Usage (PowerShell, from anywhere): & <repo>\docs\superpowers\research\bench-settings.ps1
# Writes throwaway folders under $env:TEMP\cds-bench; prints wall time and token use per config.
$root = Join-Path $env:TEMP "cds-bench"
$full = Get-Content "$PSScriptRoot\..\..\..\template\.claude\settings.json" -Raw | ConvertFrom-Json

$noSandbox = $full | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$noSandbox.PSObject.Properties.Remove('sandbox')

$slim = [ordered]@{
  enabledPlugins = [ordered]@{
    "core@campanha-dev-standards" = $false
    "security-guidance@claude-plugins-official" = $false
    "commit-commands@claude-plugins-official" = $false
    "impeccable@impeccable" = $false
    "playwright@claude-plugins-official" = $false
    "superpowers@claude-plugins-official" = $true
    "codex@openai-codex" = $true
    "typescript-lsp@claude-plugins-official" = $true
  }
  model = "opus"
  env = @{ CLAUDE_CODE_SUBAGENT_MODEL = "sonnet" }
  permissions = @{ deny = @("Read(./.env)", "Read(./.env.*)", "Bash(git * --no-verify*)"); allow = @("Read(./.env.example)") }
}

$configs = [ordered]@{ full = $full; nosandbox = $noSandbox; slim = $slim }
$prompt = "Run these three Bash commands one at a time, each in its own tool call: echo 1, then echo 2, then echo 3. Then reply only: done."

foreach ($name in $configs.Keys) {
  $dir = Join-Path $root $name
  New-Item -ItemType Directory -Force "$dir\.claude" | Out-Null
  $configs[$name] | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 "$dir\.claude\settings.json"
  Push-Location $dir
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $null = claude -p $prompt --model sonnet --output-format json --permission-mode bypassPermissions 2>$null
  $sw.Stop()
  Pop-Location

  # Token use from Claude's own session log for that folder (newest transcript).
  $proj = Get-ChildItem "$env:USERPROFILE\.claude\projects" -Directory | ? Name -like "*cds-bench-$name" | Select -First 1
  $log = Get-ChildItem $proj.FullName -Filter *.jsonl | Sort LastWriteTime -Desc | Select -First 1
  $u = Get-Content $log.FullName | % { $_ | ConvertFrom-Json } | ? { $_.type -eq 'assistant' -and $_.message.usage } | % { $_.message.usage }
  $in = { param($x) $x.input_tokens + $x.cache_read_input_tokens + $x.cache_creation_input_tokens }
  "{0,-10} wall {1,6:N1}s | startup context {2,7} tok | total input {3,7} tok | api calls {4}" -f $name, $sw.Elapsed.TotalSeconds,
    (& $in $u[0]), (($u | % { & $in $_ }) | Measure-Object -Sum).Sum, @($u).Count
}
