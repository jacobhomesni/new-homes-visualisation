$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$srcRoot = 'C:\Users\Homes NI\Downloads\ppnh-logos'
$destRoot = Join-Path $repo 'assets\logos'
$devPath = Join-Path $repo 'data\developments.json'

if (-not (Test-Path $srcRoot)) { throw "Logo folder not found: $srcRoot" }

function NormName([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant()
  return [regex]::Replace($t, '[^a-z0-9]+', '')
}

function NameFromLogoFile([string]$fileName) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
  $base = [regex]::Replace($base, '^(agent|developer)-', '', 'IgnoreCase')
  $base = ($base -replace '-', ' ' -replace '\s+', ' ').Trim()
  return $base
}

function BestMatchName([string]$fileLabel, [string[]]$candidates) {
  $fileNorm = NormName $fileLabel
  if (-not $fileNorm) { return $fileLabel }
  foreach ($c in $candidates) {
    if ((NormName $c) -eq $fileNorm) { return $c }
  }
  $best = $null
  $bestLen = -1
  foreach ($c in $candidates) {
    $n = NormName $c
    if (-not $n) { continue }
    if ($fileNorm.Contains($n) -or $n.Contains($fileNorm)) {
      if ($n.Length -gt $bestLen) {
        $best = $c
        $bestLen = $n.Length
      }
    }
  }
  if ($best) { return $best }
  return $fileLabel
}

function SplitNames([string]$raw) {
  if (-not $raw) { return @() }
  return @($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Copy logo tree
if (Test-Path $destRoot) { Remove-Item $destRoot -Recurse -Force }
New-Item -ItemType Directory -Path $destRoot | Out-Null
$copied = 0
Get-ChildItem -LiteralPath $srcRoot -Directory | ForEach-Object {
  $pathId = $_.Name
  $destDir = Join-Path $destRoot $pathId
  New-Item -ItemType Directory -Path $destDir | Out-Null
  Get-ChildItem -LiteralPath $_.FullName -File | Where-Object {
    $_.Extension -match '\.(png|jpe?g|webp|gif|svg)$'
  } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destDir $_.Name) -Force
    $script:copied++
  }
}

# Rebuild developments payload with org image refs
$raw = [System.IO.File]::ReadAllText($devPath, $utf8) | ConvertFrom-Json
$outDevs = New-Object System.Collections.Generic.List[object]
$withLogos = 0

foreach ($d in $raw.developments) {
  $pathId = [string]$d.pathId
  $agentNames = SplitNames ([string]$d.agents)
  $devNames = SplitNames ([string]$d.developers)
  $agentMap = @{}
  $devMap = @{}

  $dir = Join-Path $destRoot $pathId
  if (Test-Path -LiteralPath $dir) {
    Get-ChildItem -LiteralPath $dir -File | ForEach-Object {
      $isDev = $_.Name -match '^(?i)developer-'
      $label = NameFromLogoFile $_.Name
      $rel = ("assets/logos/$pathId/" + $_.Name) -replace '\\', '/'
      if ($isDev) {
        $name = BestMatchName $label $devNames
        $key = NormName $name
        if (-not $key) { $key = NormName $label }
        $devMap[$key] = @{ name = $name; image = $rel }
      } else {
        $name = BestMatchName $label $agentNames
        $key = NormName $name
        if (-not $key) { $key = NormName $label }
        $agentMap[$key] = @{ name = $name; image = $rel }
      }
    }
  }

  foreach ($n in $devNames) {
    $key = NormName $n
    if (-not $devMap.ContainsKey($key)) {
      $devMap[$key] = @{ name = $n; image = '' }
    } else {
      $devMap[$key].name = $n
    }
  }
  foreach ($n in $agentNames) {
    $key = NormName $n
    if (-not $agentMap.ContainsKey($key)) {
      $agentMap[$key] = @{ name = $n; image = '' }
    } else {
      $agentMap[$key].name = $n
    }
  }

  $developerOrgs = @($devMap.Values | ForEach-Object { [ordered]@{ name = $_.name; image = $_.image } })
  $agentOrgs = @($agentMap.Values | ForEach-Object { [ordered]@{ name = $_.name; image = $_.image } })
  if (@($developerOrgs + $agentOrgs | Where-Object { $_.image }).Count -gt 0) { $withLogos++ }

  [void]$outDevs.Add([ordered]@{
      pathId         = $d.pathId
      name           = $d.name
      address        = $d.address
      status         = $d.status
      homesAvailable = $d.homesAvailable
      redundant      = [bool]$d.redundant
      price          = $d.price
      developers     = $d.developers
      developerOrgs  = $developerOrgs
      agents         = $d.agents
      agentOrgs      = $agentOrgs
      url            = $d.url
      town           = $d.town
      lat            = $d.lat
      lng            = $d.lng
    })
}

$payload = [ordered]@{
  generated         = $raw.generated
  source            = $raw.source
  totalDevelopments = $outDevs.Count
  mappedCount       = $raw.mappedCount
  redundantCount    = $raw.redundantCount
  developments      = $outDevs
  agentTallies      = $raw.agentTallies
  developerTallies  = $raw.developerTallies
}

$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($devPath, $json, $utf8)
Write-Host "copied=$copied developmentsWithLogos=$withLogos total=$($outDevs.Count)"
