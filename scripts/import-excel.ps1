# Import PropertyPal New Homes audit Excel into data/audit.json (includes Has Microsite?).
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$repo = Split-Path $PSScriptRoot -Parent
$outPath = Join-Path $repo 'data\audit.json'

$xlsx = $args[0]
if (-not $xlsx) {
  $xlsx = 'C:\Users\Homes NI\Downloads\propertypal-new-homes-audit-2026-11-25 (1).xlsx'
}
if (-not (Test-Path -LiteralPath $xlsx)) { throw "Excel not found: $xlsx" }

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
try {
  $wb = $excel.Workbooks.Open($xlsx)
  $ws = $wb.Worksheets.Item(1)
  $used = $ws.UsedRange
  $rowCount = $used.Rows.Count
  $colCount = $used.Columns.Count

  $headers = @{}
  for ($c = 1; $c -le $colCount; $c++) {
    $h = ([string]$ws.Cells.Item(1, $c).Text).Trim()
    if ($h) { $headers[$h] = $c }
  }

  function Col([string]$name) {
    if (-not $headers.ContainsKey($name)) { throw "Missing column: $name" }
    return [int]$headers[$name]
  }

  function Cell([int]$r, [string]$name) {
    return ([string]$ws.Cells.Item($r, (Col $name)).Text).Trim()
  }

  function OptCell([int]$r, [string]$name) {
    if (-not $headers.ContainsKey($name)) { return '' }
    return ([string]$ws.Cells.Item($r, [int]$headers[$name]).Text).Trim()
  }

  function ParseInt($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $n = 0
    if ([int]::TryParse(($s -replace '[^\d-]', ''), [ref]$n)) { return $n }
    return $null
  }

  $devs = New-Object System.Collections.Generic.List[object]
  $agentSection = $false
  $devSection = $false
  $agentTallies = New-Object System.Collections.Generic.List[object]
  $devTallies = New-Object System.Collections.Generic.List[object]

  for ($r = 2; $r -le $rowCount; $r++) {
    $c1 = ([string]$ws.Cells.Item($r, 1).Text).Trim()
    $c2 = ([string]$ws.Cells.Item($r, 2).Text).Trim()

    if ($c1 -eq 'By agent') { $agentSection = $true; $devSection = $false; continue }
    if ($c1 -eq 'By developer') { $devSection = $true; $agentSection = $false; continue }
    if (-not $c1) { continue }

    if ($agentSection) {
      $count = ParseInt $c2
      $red = ParseInt (([string]$ws.Cells.Item($r, 3).Text).Trim())
      if ($null -eq $count) { continue }
      [void]$agentTallies.Add([ordered]@{ name = $c1; count = $count; redundant = $(if ($null -eq $red) { 0 } else { $red }) })
      continue
    }
    if ($devSection) {
      $count = ParseInt $c2
      $red = ParseInt (([string]$ws.Cells.Item($r, 3).Text).Trim())
      if ($null -eq $count) { continue }
      [void]$devTallies.Add([ordered]@{ name = $c1; count = $count; redundant = $(if ($null -eq $red) { 0 } else { $red }) })
      continue
    }

    $pathId = Cell $r 'Path ID'
    $url = Cell $r 'URL'
    if (-not $pathId -and $url -match '/(d\d+)\s*$') { $pathId = $Matches[1] }
    if (-not $pathId -and -not $url) { continue }

    $ms = OptCell $r 'Has Microsite?'
    $hasMicrosite = $null
    if ($ms -eq 'YES') { $hasMicrosite = $true }
    elseif ($ms -eq 'NO') { $hasMicrosite = $false }

    $onHniRaw = OptCell $r 'On HomesNI?'
    $onHomesNi = $null
    if ($onHniRaw -eq 'YES') { $onHomesNi = $true }
    elseif ($onHniRaw -eq 'NO') { $onHomesNi = $false }

    $homesNiUrl = OptCell $r 'HomesNI URL'
    $town = OptCell $r 'Town'
    $hniAgentRaw = OptCell $r 'HomesNI agent?'
    $homesNiAgent = $null
    if ($hniAgentRaw -eq 'YES') { $homesNiAgent = $true }
    elseif ($hniAgentRaw -eq 'NO') { $homesNiAgent = $false }

    $redundantRaw = Cell $r 'Sale agreed / redundant'
    $redundant = $redundantRaw -match '^(?i)yes|true|1$'

    [void]$devs.Add([ordered]@{
        name           = Cell $r 'Development'
        address        = Cell $r 'Address'
        town           = $town
        status         = Cell $r 'Status'
        homesAvailable = (ParseInt (Cell $r 'Homes available'))
        homesTotal     = (ParseInt (OptCell $r 'Homes total (listed)'))
        redundant      = [bool]$redundant
        hasMicrosite   = $hasMicrosite
        onHomesNi      = $onHomesNi
        homesNiUrl     = $homesNiUrl
        homesNiAgent   = $homesNiAgent
        price          = Cell $r 'Price'
        developers     = Cell $r 'Developer(s)'
        developerNote  = OptCell $r 'Developer note'
        agents         = Cell $r 'Agent(s)'
        url            = $url
        pathId         = $pathId
      })
  }

  $wb.Close($false)
}
finally {
  $excel.Quit()
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}

$yes = @($devs | Where-Object { $_.hasMicrosite -eq $true }).Count
$no = @($devs | Where-Object { $_.hasMicrosite -eq $false }).Count
$hniYes = @($devs | Where-Object { $_.onHomesNi -eq $true }).Count
$hniNo = @($devs | Where-Object { $_.onHomesNi -eq $false }).Count
$payload = [ordered]@{
  generated         = (Get-Date -Format 'yyyy-MM-dd')
  source            = [System.IO.Path]::GetFileName($xlsx)
  totalDevelopments = $devs.Count
  redundantCount    = @($devs | Where-Object { $_.redundant }).Count
  micrositeCount    = $yes
  onHomesNiCount    = $hniYes
  developments      = $devs
  agentTallies      = $agentTallies
  developerTallies  = $devTallies
}

$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outPath, $json, $utf8)
Write-Host "Wrote $outPath"
Write-Host "developments=$($devs.Count) micrositeYes=$yes micrositeNo=$no onHomesNiYes=$hniYes onHomesNiNo=$hniNo agents=$($agentTallies.Count) developers=$($devTallies.Count)"
