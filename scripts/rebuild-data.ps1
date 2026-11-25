$ErrorActionPreference = 'Stop'
$outDir = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object System.Text.UTF8Encoding $false

$audit = ([System.IO.File]::ReadAllText("$outDir\data\audit.json", $utf8) | ConvertFrom-Json)
$geo = ([System.IO.File]::ReadAllText("$outDir\data\developments.json", $utf8) | ConvertFrom-Json)

# UTF-8 bytes for the classic mojibake sequence of a curly apostrophe (E2 80 99 misread)
$badApos = [System.Text.Encoding]::UTF8.GetString([byte[]](0xC3,0xA2,0xE2,0x82,0xAC,0xE2,0x84,0xA2))
$pound = [char]0x00A3

function CleanText([string]$s) {
  if ($null -eq $s) { return '' }
  $t = [string]$s
  $t = $t.Replace('&amp;', '&')
  $t = $t.Replace('&#x27;', "'")
  $t = $t.Replace('&apos;', "'")
  $t = $t.Replace('&#39;', "'")
  $t = $t.Replace('&quot;', '"')
  $t = $t.Replace('&lt;', '<')
  $t = $t.Replace('&gt;', '>')
  if ($badApos) { $t = $t.Replace($badApos, "'") }
  $t = $t.Replace([char]0x2019, [char]0x0027)
  $t = $t.Replace([char]0x2018, [char]0x0027)
  $t = $t.Replace([char]0xFFFD, [char]0x0027)
  # Collapse L'derry / O'Hagan when a stray T sneaks in after replacement
  $t = [regex]::Replace($t, "L'+T?derry", "L'derry")
  $t = [regex]::Replace($t, "O'+T?Hagan", "O'Hagan")
  if ($t.StartsWith('"') -and $t.EndsWith('"') -and $t.Length -gt 1) {
    $t = $t.Substring(1, $t.Length - 2)
  }
  $t = ($t -replace '\s+', ' ').Trim()
  return $t
}

function FixPrice([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
  $t = [string]$raw
  if ($t -match '(?i)coming soon|price not provided|poa|sale agreed|unavailable') {
    return $Matches[0]
  }
  $nums = @([regex]::Matches($t, '\d{1,3}(?:,\d{3})+|\d{4,}') | ForEach-Object { $_.Value })
  if ($nums.Count -ge 2) { return "$pound$($nums[0]) to $pound$($nums[1])" }
  if ($nums.Count -ge 1) { return "$pound$($nums[0])" }
  return (CleanText $t)
}

$byId = @{}
foreach ($d in $audit.developments) { $byId[$d.pathId] = $d }

$out = New-Object System.Collections.Generic.List[object]
foreach ($g in $geo.developments) {
  $src = $byId[$g.pathId]
  $name = CleanText ($(if ($src) { $src.name } else { $g.name }))
  $address = CleanText ($(if ($src) { $src.address } else { $g.address }))
  $priceRaw = if ($src -and $src.price) { [string]$src.price } else { [string]$g.price }
  $devOrgs = @()
  if ($g.developerOrgs) { $devOrgs = @($g.developerOrgs) }
  $agentOrgs = @()
  if ($g.agentOrgs) { $agentOrgs = @($g.agentOrgs) }

  # Prefer audit Excel flag; fall back to existing geo value.
  $hasMicrosite = $false
  if ($src -and $null -ne $src.hasMicrosite) { $hasMicrosite = [bool]$src.hasMicrosite }
  elseif ($null -ne $g.hasMicrosite) { $hasMicrosite = [bool]$g.hasMicrosite }

  [void]$out.Add([ordered]@{
      pathId         = $g.pathId
      name           = $name
      address        = $address
      status         = CleanText ([string]$g.status)
      homesAvailable = $g.homesAvailable
      redundant      = [bool]$g.redundant
      hasMicrosite   = $hasMicrosite
      price          = (FixPrice $priceRaw)
      developers     = CleanText ([string]$(if ($src) { $src.developers } else { $g.developers }))
      developerOrgs  = $devOrgs
      agents         = CleanText ([string]$(if ($src) { $src.agents } else { $g.agents }))
      agentOrgs      = $agentOrgs
      url            = $g.url
      town           = CleanText ([string]$g.town)
      lat            = $g.lat
      lng            = $g.lng
    })
}

$agentTallies = @(foreach ($a in $audit.agentTallies) {
  [ordered]@{ name = (CleanText $a.name); count = $a.count; redundant = $a.redundant }
})
$devTallies = @(foreach ($d in $audit.developerTallies) {
  [ordered]@{ name = (CleanText $d.name); count = $d.count; redundant = $d.redundant }
})

$payload = [ordered]@{
  generated         = (Get-Date).ToString('o')
  source            = $audit.source
  totalDevelopments = $out.Count
  mappedCount       = @($out | Where-Object { $_.lat }).Count
  redundantCount    = @($out | Where-Object { $_.redundant }).Count
  developments      = $out
  agentTallies      = $agentTallies
  developerTallies  = $devTallies
}

$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText("$outDir\data\developments.json", $json, $utf8)

$c1 = $out | Where-Object { $_.pathId -eq 'd3934' }
$c2 = $out | Where-Object { $_.pathId -eq 'd3663' }
$c3 = $out | Where-Object { $_.pathId -eq 'd2602' }
Write-Host ("d3934 [" + $c1.price + "]")
Write-Host ("d3663 [" + $c2.name + "] [" + $c2.price + "]")
Write-Host ("d2602 [" + $c3.name + "]")
$ok = @($out | Where-Object { $_.price -match '\d{3},' }).Count
Write-Host "rebuilt $($out.Count); prices-ok=$ok"
