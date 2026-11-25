# Scan PropertyPal development pages for microsite signatures.
# Sets hasMicrosite on each row in data/developments.json

$ErrorActionPreference = 'Stop'
$mapRoot = Split-Path $PSScriptRoot -Parent
$dataPath = Join-Path $mapRoot 'data\developments.json'
$progressPath = Join-Path $mapRoot 'data\microsite-scan-progress.json'

Write-Host "Loading $dataPath"
$raw = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8
$payload = $raw | ConvertFrom-Json

if ($payload.developments) {
  $developments = @($payload.developments)
  $isWrapped = $true
} elseif ($payload -is [System.Array]) {
  $developments = @($payload)
  $isWrapped = $false
} else {
  throw 'Unexpected developments.json shape'
}

Write-Host ("Developments: {0}" -f $developments.Count)

function Test-HasMicrosite([string]$html) {
  if ([string]::IsNullOrWhiteSpace($html)) { return $null }
  if ($html -match 'MicrositeHero|MicrositeWrapper|MicrositeFooter') { return $true }
  if ($html -match 'class=["'']Microsite') { return $true }
  if ($html -match '"featuredDevelopmentContent"\s*:\s*\{') { return $true }
  if ($html -match '"featuredDevelopmentContent"\s*:\s*null') { return $false }
  if ($html -match 'pp-development-content' -and $html -match 'development-images/\d+/') { return $true }
  return $false
}

$done = @{}
if (Test-Path -LiteralPath $progressPath) {
  try {
    $prev = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($row in @($prev)) {
      if ($null -ne $row.pathId -and $null -ne $row.hasMicrosite) {
        $done[[string]$row.pathId] = [bool]$row.hasMicrosite
      }
    }
    Write-Host ("Resuming with {0} cached results" -f $done.Count)
  } catch {
    Write-Host 'Could not read progress file; starting fresh.'
  }
}

# Known examples from manual inspection
$done['d3864'] = $true   # Millreagh
$done['d3596'] = $false  # Camowen

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$headers = @{
  'Accept' = 'text/html,application/xhtml+xml'
  'Accept-Language' = 'en-GB,en;q=0.9'
}

function Save-Progress {
  param($map)
  $checkpoint = foreach ($k in $map.Keys) {
    [pscustomobject]@{ pathId = $k; hasMicrosite = [bool]$map[$k] }
  }
  ($checkpoint | ConvertTo-Json -Depth 3) | Set-Content -LiteralPath $progressPath -Encoding UTF8
}

$i = 0
$ok = 0
$fail = 0
$trueCount = 0
$falseCount = 0

foreach ($dev in $developments) {
  $i++
  $pathId = [string]$dev.pathId
  $url = [string]$dev.url
  if (-not $url) {
    if ($pathId -match '^d\d+$') {
      $slug = if ($dev.name) {
        ($dev.name -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLowerInvariant()
      } else { '' }
      $url = if ($slug) { "https://www.propertypal.com/$slug/$pathId" } else { "https://www.propertypal.com/$pathId" }
    }
  }

  if ($done.ContainsKey($pathId)) {
    $dev | Add-Member -NotePropertyName hasMicrosite -NotePropertyValue ([bool]$done[$pathId]) -Force
    if ($done[$pathId]) { $trueCount++ } else { $falseCount++ }
    continue
  }

  Write-Host ("[{0}/{1}] {2} {3}" -f $i, $developments.Count, $pathId, $dev.name)

  $has = $false
  try {
    $resp = Invoke-WebRequest -Uri $url -Headers $headers -UserAgent $ua -UseBasicParsing -TimeoutSec 45
    $html = [string]$resp.Content
    $detected = Test-HasMicrosite $html
    if ($null -eq $detected) {
      Write-Host '  WARN: no clear signature; marking false'
      $has = $false
    } else {
      $has = [bool]$detected
    }
    $ok++
    Write-Host ("  => {0}" -f $has)
  } catch {
    Write-Host ("  ERROR: {0}" -f $_.Exception.Message)
    $has = $false
    $fail++
  }

  $dev | Add-Member -NotePropertyName hasMicrosite -NotePropertyValue ([bool]$has) -Force
  $done[$pathId] = [bool]$has
  if ($has) { $trueCount++ } else { $falseCount++ }

  if (($i % 10) -eq 0) {
    Save-Progress $done
    Write-Host ("  checkpoint: true={0} false={1} fail={2}" -f $trueCount, $falseCount, $fail)
  }

  Start-Sleep -Milliseconds 300
}

if ($isWrapped) {
  $payload.developments = $developments
  $outObj = $payload
} else {
  $outObj = $developments
}

$json = $outObj | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($dataPath, $json, [System.Text.UTF8Encoding]::new($false))
Save-Progress $done

Write-Host ''
Write-Host ("Done. hasMicrosite=true: {0}, false: {1}, fetchOk: {2}, fetchFail: {3}" -f $trueCount, $falseCount, $ok, $fail)
Write-Host "Updated $dataPath"
