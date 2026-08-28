# ==============================================================================
# NEXA BHARAT - Production-Ready Full-Stack Web & REST API Server (.NET / PowerShell)
# ==============================================================================

param(
    [int]$Port = 3000,
    [string]$HostBinding = "localhost"
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $ScriptDir "data"
$LeadsFile = Join-Path $DataDir "leads.json"
$ProjectsFile = Join-Path $DataDir "projects.json"

if (!(Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}
if (!(Test-Path $LeadsFile)) {
    Set-Content -Path $LeadsFile -Value "[]" -Encoding UTF8
}
if (!(Test-Path $ProjectsFile)) {
    Set-Content -Path $ProjectsFile -Value "[]" -Encoding UTF8
}

# MIME Types mapping
$MimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
    ".ttf"  = "font/ttf"
    ".csv"  = "text/csv; charset=utf-8"
}

# Helper to read JSON
function Get-LeadsData {
    try {
        $content = Get-Content -Path $LeadsFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) { return @() }
        $parsed = ConvertFrom-Json $content
        if ($parsed -is [System.Array]) {
            return @($parsed | Where-Object { $_.id })
        } elseif ($parsed.id) {
            return @($parsed)
        } else {
            return @()
        }
    } catch {
        return @()
    }
}

# Helper to save JSON
function Save-LeadsData($data) {
    $flatList = @($data | Where-Object { $_.id })
    $json = $flatList | ConvertTo-Json -Depth 10
    Set-Content -Path $LeadsFile -Value $json -Encoding UTF8
}

function Get-ProjectsData {
    try {
        $content = Get-Content -Path $ProjectsFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) { return @() }
        return ConvertFrom-Json $content
    } catch {
        return @()
    }
}

# Start HttpListener
$Listener = New-Object System.Net.HttpListener
$Prefix = "http://${HostBinding}:${Port}/"
$Listener.Prefixes.Add($Prefix)

try {
    $Listener.Start()
} catch {
    Write-Host "Failed to bind to $Prefix, attempting fallback port 8080..." -ForegroundColor Yellow
    $Port = 8080
    $Prefix = "http://${HostBinding}:${Port}/"
    $Listener = New-Object System.Net.HttpListener
    $Listener.Prefixes.Add($Prefix)
    $Listener.Start()
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  NEXA BHARAT - Full-Stack Server & REST API Engine" -ForegroundColor Yellow
Write-Host "  Running at: $Prefix" -ForegroundColor Green
Write-Host "  Admin CRM : http://${HostBinding}:${Port}/admin.html" -ForegroundColor Green
Write-Host "  Website   : http://${HostBinding}:${Port}/index.html" -ForegroundColor Green
Write-Host "  Press Ctrl+C to stop server." -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor Cyan

while ($Listener.IsListening) {
    try {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response

        # CORS Headers
        $Response.AddHeader("Access-Control-Allow-Origin", "*")
        $Response.AddHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
        $Response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")

        # Handle Preflight OPTIONS
        if ($Request.HttpMethod -eq "OPTIONS") {
            $Response.StatusCode = 200
            $Response.Close()
            continue
        }

        $RawUrl = $Request.Url.AbsolutePath
        $QueryString = $Request.Url.Query

        # -------------------------------------------------------------
        # REST API Router
        # -------------------------------------------------------------
        if ($RawUrl.StartsWith("/api/")) {
            $Response.ContentType = "application/json; charset=utf-8"

            # 1. POST /api/consultations -> Create Lead
            if ($RawUrl -eq "/api/consultations" -and $Request.HttpMethod -eq "POST") {
                $Reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                $BodyText = $Reader.ReadToEnd()
                $Reader.Close()

                $Payload = $BodyText | ConvertFrom-Json
                $Leads = @(Get-LeadsData)

                $NewId = "NB-" + (Get-Date -Format "yyyy") + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
                $NowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

                $NewLead = [PSCustomObject]@{
                    id        = $NewId
                    name      = if ($Payload.name) { $Payload.name } else { "Anonymous" }
                    phone     = if ($Payload.phone) { $Payload.phone } else { "" }
                    email     = if ($Payload.email) { $Payload.email } else { "" }
                    service   = if ($Payload.service) { $Payload.service } else { "General Construction" }
                    location  = if ($Payload.location) { $Payload.location } else { "NCR" }
                    area      = if ($Payload.area) { $Payload.area } else { "N/A" }
                    budget    = if ($Payload.budget) { $Payload.budget } else { "Standard" }
                    timeline  = if ($Payload.timeline) { $Payload.timeline } else { "Flexible" }
                    message   = if ($Payload.message) { $Payload.message } else { "" }
                    status    = "NEW"
                    notes     = "Inquiry received via website form."
                    createdAt = $NowIso
                }

                $Leads = @($NewLead) + $Leads
                Save-LeadsData $Leads

                $ResponseBody = @{
                    success = $true
                    message = "Consultation request received successfully."
                    leadId  = $NewId
                    data    = $NewLead
                } | ConvertTo-Json

                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.StatusCode = 201
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 2. GET /api/consultations -> List Leads
            if ($RawUrl -eq "/api/consultations" -and $Request.HttpMethod -eq "GET") {
                $Leads = Get-LeadsData
                
                # Check status filter
                $StatusFilter = $Request.QueryString["status"]
                $SearchQuery = $Request.QueryString["search"]

                if (![string]::IsNullOrEmpty($StatusFilter) -and $StatusFilter -ne "ALL") {
                    $Leads = @($Leads | Where-Object { $_.status -eq $StatusFilter })
                }
                if (![string]::IsNullOrEmpty($SearchQuery)) {
                    $q = $SearchQuery.ToLower()
                    $Leads = @($Leads | Where-Object { 
                        ($_.name -and $_.name.ToLower().Contains($q)) -or 
                        ($_.phone -and $_.phone.ToLower().Contains($q)) -or 
                        ($_.email -and $_.email.ToLower().Contains($q)) -or 
                        ($_.location -and $_.location.ToLower().Contains($q))
                    })
                }

                $ResponseBody = @{
                    success = $true
                    count   = $Leads.Count
                    data    = $Leads
                } | ConvertTo-Json -Depth 10

                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.StatusCode = 200
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 3. PATCH /api/consultations -> Update Lead Status & Notes
            if ($RawUrl -eq "/api/consultations" -and $Request.HttpMethod -eq "PATCH") {
                $Reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                $BodyText = $Reader.ReadToEnd()
                $Reader.Close()

                $Payload = $BodyText | ConvertFrom-Json
                $Leads = @(Get-LeadsData)
                $Found = $false

                foreach ($lead in $Leads) {
                    if ($lead.id -eq $Payload.id) {
                        if ($Payload.status) { $lead.status = $Payload.status }
                        if ($Payload.notes)  { $lead.notes = $Payload.notes }
                        $Found = $true
                        break
                    }
                }

                if ($Found) {
                    Save-LeadsData $Leads
                    $ResponseBody = @{ success = $true; message = "Lead updated successfully." } | ConvertTo-Json
                    $Response.StatusCode = 200
                } else {
                    $ResponseBody = @{ success = $false; error = "Lead not found." } | ConvertTo-Json
                    $Response.StatusCode = 404
                }

                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 4. DELETE /api/consultations -> Delete Lead
            if ($RawUrl -eq "/api/consultations" -and $Request.HttpMethod -eq "DELETE") {
                $LeadId = $Request.QueryString["id"]
                $Leads = @(Get-LeadsData)
                $Filtered = @($Leads | Where-Object { $_.id -ne $LeadId })

                Save-LeadsData $Filtered
                $ResponseBody = @{ success = $true; message = "Lead deleted." } | ConvertTo-Json
                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.StatusCode = 200
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 5. GET /api/consultations/export -> Export CSV
            if ($RawUrl -eq "/api/consultations/export" -and $Request.HttpMethod -eq "GET") {
                $Leads = Get-LeadsData
                $CsvHeader = "Lead ID,Name,Phone,Email,Service,Location,Area,Budget,Timeline,Status,Created At,Notes`r`n"
                $CsvRows = ""
                foreach ($lead in $Leads) {
                    $cleanName = if ($lead.name) { $lead.name.Replace('"', '""') } else { "" }
                    $cleanMsg  = if ($lead.notes) { $lead.notes.Replace('"', '""') } else { "" }
                    $CsvRows += "`"$($lead.id)`",`"$cleanName`",`"$($lead.phone)`",`"$($lead.email)`",`"$($lead.service)`",`"$($lead.location)`",`"$($lead.area)`",`"$($lead.budget)`",`"$($lead.timeline)`",`"$($lead.status)`",`"$($lead.createdAt)`",`"$cleanMsg`"`r`n"
                }
                $CsvContent = $CsvHeader + $CsvRows
                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($CsvContent)

                $Response.ContentType = "text/csv; charset=utf-8"
                $Response.AddHeader("Content-Disposition", "attachment; filename=nexa_bharat_leads.csv")
                $Response.StatusCode = 200
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 6. GET /api/stats -> KPI Metrics
            if ($RawUrl -eq "/api/stats" -and $Request.HttpMethod -eq "GET") {
                $Leads = Get-LeadsData
                $TotalCount = $Leads.Count
                $NewCount = ($Leads | Where-Object { $_.status -eq "NEW" }).Count
                $SiteVisits = ($Leads | Where-Object { $_.status -eq "SITE_VISIT_SCHEDULED" }).Count
                $Proposals = ($Leads | Where-Object { $_.status -eq "PROPOSAL_SENT" }).Count
                $WonCount = ($Leads | Where-Object { $_.status -eq "WON" }).Count

                $ResponseBody = @{
                    success = $true
                    data = @{
                        totalLeads          = $TotalCount
                        newLeads            = $NewCount
                        siteVisitsScheduled = $SiteVisits
                        proposalsSent       = $Proposals
                        wonProjects         = $WonCount
                        estimatedPipeline   = "₹14.85 Cr"
                        conversionRate      = if ($TotalCount -gt 0) { [math]::Round(($WonCount / $TotalCount) * 100, 1) } else { 0 }
                    }
                } | ConvertTo-Json

                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.StatusCode = 200
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 7. POST /api/estimate -> Dynamic Cost Calculation
            if ($RawUrl -eq "/api/estimate" -and $Request.HttpMethod -eq "POST") {
                $Reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                $BodyText = $Reader.ReadToEnd()
                $Reader.Close()

                $Payload = $BodyText | ConvertFrom-Json
                $Type = if ($Payload.type) { $Payload.type } else { "construction" }
                $Area = if ($Payload.area) { [int]$Payload.area } else { 1200 }
                $Tier = if ($Payload.tier) { $Payload.tier } else { "premium" }

                $RateMap = @{
                    "construction" = @{ "standard" = @{ min = 1650; max = 1850 }; "premium" = @{ min = 2100; max = 2500 }; "luxury" = @{ min = 2900; max = 3600 } }
                    "interiors"    = @{ "standard" = @{ min = 1200; max = 1500 }; "premium" = @{ min = 1800; max = 2400 }; "luxury" = @{ min = 2800; max = 4000 } }
                    "renovation"   = @{ "standard" = @{ min = 900;  max = 1250 }; "premium" = @{ min = 1400; max = 1900 }; "luxury" = @{ min = 2200; max = 3100 } }
                    "modular-kitchen" = @{ "standard" = @{ min = 1300; max = 1700 }; "premium" = @{ min = 2000; max = 2800 }; "luxury" = @{ min = 3200; max = 4800 } }
                }

                $Rates = $RateMap[$Type][$Tier]
                $MinTotal = $Rates.min * $Area
                $MaxTotal = $Rates.max * $Area
                $AvgTotal = ($MinTotal + $MaxTotal) / 2

                $Breakdown = @{
                    civilMaterials    = [math]::Round($AvgTotal * 0.45)
                    laborAndMEP       = [math]::Round($AvgTotal * 0.25)
                    joineryAndFinishes= [math]::Round($AvgTotal * 0.20)
                    supervisionTaxes  = [math]::Round($AvgTotal * 0.10)
                }

                $ResponseBody = @{
                    success     = $true
                    type        = $Type
                    area        = $Area
                    tier        = $Tier
                    rateRange   = "₹$($Rates.min) - ₹$($Rates.max) / sq.ft."
                    minEstimate = $MinTotal
                    maxEstimate = $MaxTotal
                    breakdown   = $Breakdown
                } | ConvertTo-Json

                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.StatusCode = 200
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # 8. GET /api/projects -> Projects CMS
            if ($RawUrl -eq "/api/projects" -and $Request.HttpMethod -eq "GET") {
                $Projects = Get-ProjectsData
                $ResponseBody = @{ success = $true; count = $Projects.Count; data = $Projects } | ConvertTo-Json -Depth 10
                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
                $Response.StatusCode = 200
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()
                continue
            }

            # Fallback 404 for unknown API
            $ResponseBody = @{ success = $false; error = "Endpoint not found" } | ConvertTo-Json
            $Buffer = [System.Text.Encoding]::UTF8.GetBytes($ResponseBody)
            $Response.StatusCode = 404
            $Response.ContentLength64 = $Buffer.Length
            $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
            $Response.Close()
            continue
        }

        # -------------------------------------------------------------
        # Static File Serving Router
        # -------------------------------------------------------------
        $NormalizedUrl = $RawUrl.TrimStart("/").Replace("/", "\")
        if ([string]::IsNullOrWhiteSpace($NormalizedUrl)) {
            $NormalizedUrl = "index.html"
        }

        $FilePath = Join-Path $ScriptDir $NormalizedUrl

        if (Test-Path $FilePath -PathType Leaf) {
            $Extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
            $ContentType = if ($MimeTypes.ContainsKey($Extension)) { $MimeTypes[$Extension] } else { "application/octet-stream" }
            $Response.ContentType = $ContentType

            $Bytes = [System.IO.File]::ReadAllBytes($FilePath)
            $Response.ContentLength64 = $Bytes.Length
            $Response.StatusCode = 200
            $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
            $Response.Close()
        } else {
            # 404 Not Found
            $NotFoundHtml = "<html><body style='font-family:sans-serif;text-align:center;padding:50px;'><h2>404 - Page Not Found</h2><p><a href='/index.html'>Return to NEXA BHARAT Home</a></p></body></html>"
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($NotFoundHtml)
            $Response.StatusCode = 404
            $Response.ContentType = "text/html; charset=utf-8"
            $Response.ContentLength64 = $Bytes.Length
            $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
            $Response.Close()
        }

    } catch {
        Write-Host "Error handling request: $_" -ForegroundColor Red
        try {
            $Response.StatusCode = 500
            $Response.Close()
        } catch {}
    }
}
