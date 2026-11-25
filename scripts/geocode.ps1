$ErrorActionPreference = 'Stop'
$outDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
# When run from repo: pp-new-homes-map/scripts -> outDir is pp-new-homes-map
$outDir = Split-Path $PSScriptRoot -Parent
$audit = Get-Content -Raw "$outDir\data\audit.json" | ConvertFrom-Json

$towns = @{}
$pairs = @(
  @('belfast', 54.5973, -5.9301),
  @('lisburn', 54.5162, -6.058),
  @('newtownabbey', 54.68, -5.91),
  @('bangor', 54.653, -5.669),
  @('newtownards', 54.592, -5.693),
  @('carrickfergus', 54.715, -5.808),
  @('larne', 54.85, -5.81),
  @('antrim', 54.717, -6.207),
  @('ballymena', 54.863, -6.276),
  @('ballyclare', 54.751, -6.001),
  @('ballycastle', 55.204, -6.243),
  @('ballymoney', 55.071, -6.51),
  @('portrush', 55.208, -6.654),
  @('portstewart', 55.181, -6.714),
  @('coleraine', 55.133, -6.668),
  @('limavady', 55.051, -6.951),
  @('derry', 54.996, -7.309),
  @('londonderry', 54.996, -7.309),
  @('magherafelt', 54.755, -6.606),
  @('maghera', 54.86, -6.67),
  @('cookstown', 54.643, -6.746),
  @('omagh', 54.598, -7.31),
  @('strabane', 54.827, -7.463),
  @('dungannon', 54.504, -6.764),
  @('coalisland', 54.54, -6.7),
  @('armagh', 54.35, -6.655),
  @('portadown', 54.422, -6.444),
  @('lurgan', 54.462, -6.331),
  @('craigavon', 54.45, -6.39),
  @('newry', 54.176, -6.349),
  @('banbridge', 54.351, -6.27),
  @('downpatrick', 54.329, -5.715),
  @('newcastle', 54.215, -5.89),
  @('holywood', 54.639, -5.821),
  @('dundonald', 54.592, -5.81),
  @('carryduff', 54.534, -5.887),
  @('comber', 54.549, -5.744),
  @('ballynahinch', 54.403, -5.895),
  @('moira', 54.48, -6.23),
  @('hillsborough', 54.462, -6.083),
  @('dunmurry', 54.55, -6.0),
  @('enniskillen', 54.346, -7.634),
  @('lisnaskea', 54.25, -7.44),
  @('irvinestown', 54.47, -7.63),
  @('castlederg', 54.707, -7.595),
  @('doagh', 54.735, -6.046),
  @('crumlin', 54.62, -6.21),
  @('templepatrick', 54.7, -6.09),
  @('greenisland', 54.7, -5.87),
  @('whitehead', 54.75, -5.71),
  @('glengormley', 54.67, -5.96),
  @('jordanstown', 54.69, -5.88),
  @('malone', 54.56, -5.95),
  @('finaghy', 54.56, -5.98),
  @('ormeau', 54.58, -5.92),
  @('kilkeel', 54.06, -5.99),
  @('warrenpoint', 54.1, -6.25),
  @('rostrevor', 54.1, -6.2),
  @('portaferry', 54.38, -5.54),
  @('donaghadee', 54.64, -5.53),
  @('groomsport', 54.67, -5.62),
  @('helens bay', 54.66, -5.74),
  @('crawfordsburn', 54.66, -5.72),
  @('saintfield', 54.46, -5.83),
  @('dromore', 54.41, -6.15),
  @('waringstown', 54.43, -6.3),
  @('richhill', 54.37, -6.55),
  @('markethill', 54.3, -6.52),
  @('keady', 54.25, -6.7),
  @('tandragee', 54.35, -6.41),
  @('ahoghill', 54.87, -6.35),
  @('randalstown', 54.75, -6.3),
  @('bushmills', 55.2, -6.52),
  @('cushendall', 55.08, -6.06),
  @('ballinamallard', 54.42, -7.6),
  @('tempo', 54.38, -7.45),
  @('belleek', 54.48, -8.09),
  @('castlerock', 55.17, -6.79),
  @('eglinton', 55.04, -7.18),
  @('draperstown', 54.79, -6.78),
  @('garvagh', 54.98, -6.66),
  @('portglenone', 54.87, -6.47),
  @('ballygawley', 54.46, -7.03),
  @('fintona', 54.5, -7.32),
  @('aughnacloy', 54.41, -6.98),
  @('stewartstown', 54.58, -6.68),
  @('dollingstown', 54.45, -6.28),
  @('gilford', 54.37, -6.33),
  @('moy', 54.45, -6.69),
  @('kesh', 54.52, -7.72),
  @('garrison', 54.4, -8.0),
  @('derrygonnelly', 54.4, -7.85),
  @('ederney', 54.5, -7.6),
  @('newtownbutler', 54.2, -7.36),
  @('lisbellaw', 54.32, -7.55),
  @('ballyhackamore', 54.6, -5.86),
  @('strandtown', 54.6, -5.88),
  @('sydenham', 54.61, -5.88),
  @('knock', 54.59, -5.85),
  @('cavehill', 54.65, -5.95),
  @('andersonstown', 54.58, -5.99),
  @('poleglass', 54.56, -6.02),
  @('moneyreagh', 54.53, -5.82),
  @('ballygowan', 54.52, -5.79),
  @('killinchy', 54.48, -5.68),
  @('killyleagh', 54.4, -5.65),
  @('ardglass', 54.26, -5.61),
  @('strangford', 54.37, -5.56),
  @('greyabbey', 54.53, -5.56),
  @('ballywalter', 54.54, -5.48),
  @('millisle', 54.61, -5.53),
  @('magheralin', 54.47, -6.26),
  @('aghalee', 54.52, -6.22),
  @('ballinderry', 54.54, -6.16),
  @('derriaghy', 54.55, -6.02),
  @('lambeg', 54.53, -6.04),
  @('seahill', 54.66, -5.8),
  @('carnmoney', 54.68, -5.94),
  @('monkstown', 54.69, -5.91),
  @('whiteabbey', 54.68, -5.9),
  @('islandmagee', 54.78, -5.71),
  @('broughshane', 54.89, -6.21),
  @('clough', 54.3, -5.9),
  @('castlewellan', 54.26, -5.92),
  @('rathfriland', 54.24, -6.16),
  @('crossgar', 54.4, -5.76),
  @('annalong', 54.11, -5.9),
  @('bessbrook', 54.19, -6.4),
  @('camlough', 54.18, -6.42),
  @('poyntzpass', 54.29, -6.38),
  @('loughgall', 54.4, -6.6),
  @('caledon', 54.35, -6.84),
  @('coagh', 54.65, -6.62),
  @('moneymore', 54.69, -6.71),
  @('bellaghy', 54.81, -6.52),
  @('castledawson', 54.78, -6.56),
  @('toome', 54.75, -6.46),
  @('toomebridge', 54.75, -6.46),
  @('swatragh', 54.9, -6.66),
  @('upperlands', 54.88, -6.65),
  @('kilrea', 54.95, -6.55),
  @('macosquin', 55.1, -6.72),
  @('articlave', 55.14, -6.78),
  @('portballintrae', 55.22, -6.54),
  @('ballintoy', 55.23, -6.37),
  @('cushendun', 55.13, -6.04),
  @('waterfoot', 55.06, -6.06),
  @('carnlough', 54.99, -5.99),
  @('glenarm', 54.97, -5.95),
  @('ballygalley', 54.9, -5.86),
  @('donemana', 54.87, -7.3),
  @('claudy', 54.91, -7.15),
  @('feeny', 54.9, -7.0),
  @('dungiven', 54.93, -6.92),
  @('ballykelly', 55.04, -7.02),
  @('greysteel', 55.03, -7.12),
  @('newbuildings', 54.97, -7.35),
  @('culmore', 55.05, -7.27),
  @('waterside', 54.99, -7.3),
  @('strathfoyle', 55.01, -7.28),
  @('bt1', 54.597, -5.93),
  @('bt2', 54.595, -5.93),
  @('bt3', 54.61, -5.9),
  @('bt4', 54.6, -5.87),
  @('bt5', 54.59, -5.88),
  @('bt6', 54.58, -5.9),
  @('bt7', 54.58, -5.93),
  @('bt8', 54.54, -5.9),
  @('bt9', 54.57, -5.95),
  @('bt10', 54.56, -5.98),
  @('bt11', 54.58, -5.99),
  @('bt12', 54.59, -5.96),
  @('bt13', 54.61, -5.95),
  @('bt14', 54.63, -5.95),
  @('bt15', 54.64, -5.93),
  @('bt16', 54.59, -5.81),
  @('bt17', 54.55, -6.0),
  @('bt18', 54.64, -5.82),
  @('bt19', 54.66, -5.67),
  @('bt20', 54.65, -5.67),
  @('bt21', 54.64, -5.55),
  @('bt22', 54.55, -5.55),
  @('bt23', 54.59, -5.69),
  @('bt24', 54.4, -5.89),
  @('bt25', 54.41, -6.15),
  @('bt26', 54.46, -6.08),
  @('bt27', 54.5, -6.05),
  @('bt28', 54.51, -6.05),
  @('bt29', 54.62, -6.21),
  @('bt30', 54.33, -5.72),
  @('bt31', 54.26, -5.92),
  @('bt32', 54.35, -6.27),
  @('bt33', 54.22, -5.89),
  @('bt34', 54.18, -6.35),
  @('bt35', 54.18, -6.4),
  @('bt36', 54.68, -5.95),
  @('bt37', 54.68, -5.9),
  @('bt38', 54.72, -5.81),
  @('bt39', 54.75, -6.0),
  @('bt40', 54.85, -5.81),
  @('bt41', 54.72, -6.21),
  @('bt42', 54.86, -6.28),
  @('bt43', 54.86, -6.28),
  @('bt44', 54.95, -6.2),
  @('bt45', 54.76, -6.61),
  @('bt46', 54.86, -6.67),
  @('bt47', 54.99, -7.28),
  @('bt48', 54.997, -7.32),
  @('bt49', 55.05, -6.95),
  @('bt51', 55.13, -6.67),
  @('bt52', 55.13, -6.67),
  @('bt53', 55.07, -6.51),
  @('bt54', 55.2, -6.24),
  @('bt55', 55.18, -6.71),
  @('bt56', 55.2, -6.65),
  @('bt57', 55.2, -6.52),
  @('bt60', 54.35, -6.65),
  @('bt61', 54.35, -6.65),
  @('bt62', 54.42, -6.44),
  @('bt63', 54.42, -6.44),
  @('bt64', 54.45, -6.39),
  @('bt65', 54.45, -6.35),
  @('bt66', 54.46, -6.33),
  @('bt67', 54.48, -6.23),
  @('bt68', 54.5, -6.76),
  @('bt69', 54.5, -6.76),
  @('bt70', 54.64, -6.75),
  @('bt71', 54.5, -6.76),
  @('bt74', 54.35, -7.63),
  @('bt75', 54.45, -7.3),
  @('bt76', 54.5, -7.3),
  @('bt77', 54.41, -6.98),
  @('bt78', 54.6, -7.31),
  @('bt79', 54.6, -7.31),
  @('bt80', 54.64, -6.75),
  @('bt81', 54.71, -7.6),
  @('bt82', 54.83, -7.46),
  @('bt92', 54.25, -7.44),
  @('bt93', 54.5, -7.7),
  @('bt94', 54.4, -7.6)
)
foreach ($p in $pairs) { $towns[$p[0]] = @([double]$p[1], [double]$p[2]) }

function NormalizeTown([string]$s) {
  if (-not $s) { return '' }
  $t = $s.ToLowerInvariant().Trim()
  $t = $t -replace '^["'']+|["'']+$', ''
  $t = $t -replace '\s+', ' '
  return $t
}

function ExtractPlace([string]$addr) {
  $parts = @($addr -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $candidates = @()
  for ($i = $parts.Count - 1; $i -ge 0; $i--) {
    $p = $parts[$i]
    if ($p -match '^(BT\d{1,2})(?:\s*\d[A-Z]{2})?$') {
      $candidates += $Matches[1]
      continue
    }
    if ($p -match '^(BT\d{1,2})\b') { $candidates += $Matches[1] }
    if ($p -match '^\d') { continue }
    $candidates += $p
  }
  return $candidates
}

function LookupTown([string]$name) {
  $n = NormalizeTown $name
  if ($towns.ContainsKey($n)) { return @{ town = $n; coords = $towns[$n] } }
  if ($n -match '^(bt\d{1,2})') {
    $bt = $Matches[1]
    if ($towns.ContainsKey($bt)) { return @{ town = $bt.ToUpper(); coords = $towns[$bt] } }
  }
  $n2 = ($n -replace '\s*bt\d+.*$', '').Trim()
  if ($towns.ContainsKey($n2)) { return @{ town = $n2; coords = $towns[$n2] } }
  foreach ($k in $towns.Keys) {
    if ($k.Length -lt 4) { continue }
    if ($n2 -eq $k -or $n2.Contains($k) -or $k.Contains($n2)) {
      if ($n2.Length -ge 4) { return @{ town = $k; coords = $towns[$k] } }
    }
  }
  return $null
}

function FixPrice([string]$raw) {
  if (-not $raw) { return '' }
  if ($raw -match '(?i)coming soon|price not provided|poa|sale agreed|unavailable') {
    return ($raw -replace '[^\x20-\x7E]', '').Trim()
  }
  $nums = [regex]::Matches($raw, '[\d,]+') | ForEach-Object { $_.Value }
  if ($nums.Count -ge 2 -and $raw -match '(?i)to|from') {
    return "From £$($nums[0]) to £$($nums[1])"
  }
  if ($nums.Count -ge 1) { return "£$($nums[0])" }
  return ($raw -replace '[^\x20-\x7E]', '').Trim()
}

$geo = New-Object System.Collections.Generic.List[object]
$miss = New-Object System.Collections.Generic.List[string]

foreach ($d in $audit.developments) {
  $lat = $null; $lng = $null; $matched = ''
  foreach ($c in (ExtractPlace ([string]$d.address))) {
    $hit = LookupTown $c
    if ($hit) {
      $lat = $hit.coords[0]; $lng = $hit.coords[1]; $matched = $hit.town
      break
    }
  }
  if (-not $matched) {
    foreach ($c in (ExtractPlace ([string]$d.name))) {
      $hit = LookupTown $c
      if ($hit) {
        $lat = $hit.coords[0]; $lng = $hit.coords[1]; $matched = $hit.town
        break
      }
    }
  }
  if (-not $matched) { [void]$miss.Add("$($d.pathId)|$($d.address)") }

  $jitterLat = 0; $jitterLng = 0
  if ($null -ne $lat -and $d.pathId) {
    $h = [Math]::Abs(($d.pathId).GetHashCode())
    $jitterLat = (($h % 100) - 50) / 12000.0
    $jitterLng = ((([int]($h / 100)) % 100) - 50) / 12000.0
  }

  [void]$geo.Add([pscustomobject]@{
      pathId         = $d.pathId
      name           = (([string]$d.name) -replace '^"|"$', '')
      address        = (([string]$d.address) -replace '^"|"$', '')
      status         = $d.status
      homesAvailable = $d.homesAvailable
      redundant      = [bool]$d.redundant
      price          = (FixPrice ([string]$d.price))
      developers     = $d.developers
      agents         = $d.agents
      url            = $d.url
      town           = $matched
      lat            = if ($null -ne $lat) { [math]::Round($lat + $jitterLat, 6) } else { $null }
      lng            = if ($null -ne $lng) { [math]::Round($lng + $jitterLng, 6) } else { $null }
    })
}

Write-Host "geocoded=$(@($geo | Where-Object { $_.lat }).Count)/$($geo.Count) missed=$($miss.Count)"
$miss | Select-Object -First 50 | ForEach-Object { Write-Host $_ }

$payload = [pscustomobject]@{
  generated          = (Get-Date).ToString('o')
  source             = $audit.source
  totalDevelopments  = $geo.Count
  mappedCount        = @($geo | Where-Object { $_.lat }).Count
  redundantCount     = @($geo | Where-Object { $_.redundant }).Count
  developments       = $geo
  agentTallies       = $audit.agentTallies
  developerTallies   = $audit.developerTallies
}

$json = $payload | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText("$outDir\data\developments.json", $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "wrote developments.json"
