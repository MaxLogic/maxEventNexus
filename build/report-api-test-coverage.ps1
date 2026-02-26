param(
  [switch]$EnforceTarget
)

$ErrorActionPreference = 'Stop'

$lRootDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$lTokenPath = Join-Path $lRootDir 'build/api-test-coverage.tokens'
$lTargetPath = Join-Path $lRootDir 'build/api-test-coverage-target.txt'
$lOutputPath = Join-Path $lRootDir 'build/analysis/test-api-coverage.md'

if (-not (Test-Path -LiteralPath $lTokenPath)) {
  Write-Error "Token list not found: $lTokenPath"
  exit 2
}

$lTestPaths = @(
  (Join-Path $lRootDir 'tests/src/MaxEventNexus.Main.Tests.pas'),
  (Join-Path $lRootDir 'tests/MaxEventNexusTests.dpr')
)

$lTokens = @()
foreach ($lRawLine in Get-Content -LiteralPath $lTokenPath) {
  $lLine = ($lRawLine -replace '#.*$', '').Trim()
  if ([string]::IsNullOrWhiteSpace($lLine)) {
    continue
  }
  $lTokens += $lLine
}

if ($lTokens.Count -eq 0) {
  Write-Error "No coverage tokens loaded from $lTokenPath"
  exit 2
}

$lCovered = 0
$lUncovered = @()
foreach ($lToken in $lTokens) {
  $lFound = $false
  foreach ($lTestPath in $lTestPaths) {
    if (Select-String -Path $lTestPath -SimpleMatch -Quiet -Pattern $lToken) {
      $lFound = $true
      break
    }
  }

  if ($lFound) {
    $lCovered++
  } else {
    $lUncovered += $lToken
  }
}

$lTotal = $lTokens.Count
$lPercent = [int][Math]::Round(($lCovered * 100.0) / $lTotal, 0, [MidpointRounding]::AwayFromZero)

$lLines = @(
  '# API Test Coverage Proxy',
  '',
  "- Tokens covered: $lCovered / $lTotal",
  "- Coverage percent: $lPercent%"
)

if ($lUncovered.Count -gt 0) {
  $lLines += '- Uncovered tokens:'
  foreach ($lToken in $lUncovered) {
    $lLines += "  - ``$lToken``"
  }
}

$lOutputDir = Split-Path -Parent $lOutputPath
if (-not (Test-Path -LiteralPath $lOutputDir)) {
  New-Item -ItemType Directory -Path $lOutputDir | Out-Null
}

Set-Content -LiteralPath $lOutputPath -Value $lLines -Encoding Ascii

if ($EnforceTarget.IsPresent) {
  if (-not (Test-Path -LiteralPath $lTargetPath)) {
    Write-Error "Target file not found: $lTargetPath"
    exit 2
  }

  $lTargetRaw = (Get-Content -LiteralPath $lTargetPath -Raw).Trim()
  [int]$lTarget = 0
  if (-not [int]::TryParse($lTargetRaw, [ref]$lTarget)) {
    Write-Error "Invalid coverage target in ${lTargetPath}: $lTargetRaw"
    exit 2
  }

  if ($lPercent -lt $lTarget) {
    Write-Host "FAIL: API coverage proxy $lPercent% is below target $lTarget%."
    Write-Host "      See report: $lOutputPath"
    exit 1
  }
}

Write-Host "API coverage proxy: $lCovered/$lTotal ($lPercent%)."
Write-Host "Report written: $lOutputPath"
