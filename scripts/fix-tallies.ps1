$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$path = Join-Path $repo 'data\developments.json'
$apath = Join-Path $repo 'data\audit.json'

$data = ([System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json)

function Build-Tallies($devs, $field) {
  $map = @{}
  foreach ($d in $devs) {
    $raw = [string]$d.$field
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $names = @($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    foreach ($n in $names) {
      if (-not $map.ContainsKey($n)) { $map[$n] = @{ count = 0; redundant = 0 } }
      $map[$n].count++
      if ($d.redundant) { $map[$n].redundant++ }
    }
  }
  return @(
    $map.GetEnumerator() |
      Sort-Object { -$_.Value.count }, { $_.Key } |
      ForEach-Object {
        [ordered]@{ name = $_.Key; count = [int]$_.Value.count; redundant = [int]$_.Value.redundant }
      }
  )
}

$agentTallies = @(Build-Tallies $data.developments 'agents')
$devTallies = @(Build-Tallies $data.developments 'developers')

$payload = [ordered]@{
  generated         = $data.generated
  source            = $data.source
  totalDevelopments = $data.totalDevelopments
  mappedCount       = $data.mappedCount
  redundantCount    = $data.redundantCount
  developments      = $data.developments
  agentTallies      = $agentTallies
  developerTallies  = $devTallies
}
[System.IO.File]::WriteAllText($path, ($payload | ConvertTo-Json -Depth 10), $utf8)

$audit = ([System.IO.File]::ReadAllText($apath, $utf8) | ConvertFrom-Json)
$auditPayload = [ordered]@{
  generated         = $audit.generated
  source            = $audit.source
  totalDevelopments = $audit.totalDevelopments
  redundantCount    = $audit.redundantCount
  micrositeCount    = $audit.micrositeCount
  onHomesNiCount    = $audit.onHomesNiCount
  developments      = $audit.developments
  agentTallies      = $agentTallies
  developerTallies  = $devTallies
}
[System.IO.File]::WriteAllText($apath, ($auditPayload | ConvertTo-Json -Depth 10), $utf8)

$yes = @($data.developments | Where-Object { $_.onHomesNi -eq $true }).Count
$ms = @($data.developments | Where-Object { $_.hasMicrosite -eq $true }).Count
Write-Host "onHomesNi=$yes microsite=$ms agents=$($agentTallies.Count) developers=$($devTallies.Count)"
