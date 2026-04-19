[CmdletBinding()]
param(
    [string]$LibraryRoot = "",
    [switch]$ForceRedownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($LibraryRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent $scriptDirectory
    $LibraryRoot = Join-Path $projectRoot "Docu Simufire"
}

function Invoke-WebRequestCompat {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers = @{},
        [string]$OutFile = "",
        [int]$MaximumRedirection = 10
    )

    $params = @{
        Uri = $Uri
        Headers = $Headers
        MaximumRedirection = $MaximumRedirection
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $params.UseBasicParsing = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        $params.OutFile = $OutFile
    }

    return Invoke-WebRequest @params
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Test-IsPdfFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 4) {
            return $false
        }

        $buffer = New-Object byte[] 4
        [void]$stream.Read($buffer, 0, 4)
        $signature = [System.Text.Encoding]::ASCII.GetString($buffer)
        return $signature -eq "%PDF"
    }
    finally {
        $stream.Dispose()
    }
}

function Get-ResolvedUri {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUri,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    $base = [System.Uri]::new($BaseUri)
    return [System.Uri]::new($base, $Candidate).AbsoluteUri
}

function Get-FirstRegexMatchValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        $match = [System.Text.RegularExpressions.Regex]::Match(
            $Text,
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }

    return $null
}

function Resolve-SpringerPdfUrl {
    param([Parameter(Mandatory = $true)][string]$Doi)

    $escaped = [System.Uri]::EscapeDataString($Doi)
    return "https://link.springer.com/content/pdf/$escaped.pdf"
}

function Resolve-FigshareDownloadUrl {
    param([Parameter(Mandatory = $true)][string]$ArticleUrl)

    if ($ArticleUrl -notmatch "/(\d+)$") {
        throw "No se pudo extraer el id de Figshare desde '$ArticleUrl'."
    }

    $articleId = $Matches[1]
    $apiUrl = "https://api.figshare.com/v2/articles/$articleId"
    $article = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "SimufireResearchDownloader/1.0" }

    if (-not $article.files -or $article.files.Count -eq 0) {
        throw "El articulo de Figshare '$ArticleUrl' no expone ficheros descargables."
    }

    return $article.files[0].download_url
}

function Resolve-HtmlDownloadUrl {
    param([Parameter(Mandatory = $true)][string]$PageUrl)

    $response = Invoke-WebRequestCompat -Uri $PageUrl -Headers @{ "User-Agent" = "Mozilla/5.0 SimufireResearchDownloader/1.0" }
    $html = [string]$response.Content

    $scienceDirectMatch = [System.Text.RegularExpressions.Regex]::Match(
        $html,
        '"pdfDownload":\{"isPdfFullText":[^}]*"md5":"([^"]+)"\s*,\s*"pid":"([^"]+)"',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($scienceDirectMatch.Success) {
        $pageUri = [System.Uri]::new($PageUrl)
        $basePath = $pageUri.AbsolutePath.TrimEnd("/")
        return "{0}://{1}{2}/pdfft?md5={3}&pid={4}" -f $pageUri.Scheme, $pageUri.Host, $basePath, $scienceDirectMatch.Groups[1].Value, $scienceDirectMatch.Groups[2].Value
    }

    $direct = Get-FirstRegexMatchValue -Text $html -Patterns @(
        'citation_pdf_url"\s+content="([^"]+)"',
        'href="([^"]+\.pdf(?:\?[^"]+)?)"',
        "href='([^']+\.pdf(?:\?[^']+)?)'",
        '(https?://[^"''<>\s]+\.pdf(?:\?[^"''<>\s]+)?)',
        'href="([^"]*cloudfront\.net[^"]+)"'
    )

    if ($direct) {
        return (Get-ResolvedUri -BaseUri $PageUrl -Candidate $direct)
    }

    $figsharePage = Get-FirstRegexMatchValue -Text $html -Patterns @(
        'href="([^"]*figshare\.com/articles/[^"]+/(\d+))"',
        "href='([^']*figshare\.com/articles/[^']+/(\d+))'"
    )

    if ($figsharePage) {
        return Resolve-FigshareDownloadUrl -ArticleUrl (Get-ResolvedUri -BaseUri $PageUrl -Candidate $figsharePage)
    }

    throw "No se encontro una URL de descarga util en '$PageUrl'."
}

function Resolve-PmcPdfUrl {
    param([Parameter(Mandatory = $true)][string]$ArticleUrl)

    $response = Invoke-WebRequestCompat -Uri $ArticleUrl -Headers @{ "User-Agent" = "Mozilla/5.0 SimufireResearchDownloader/1.0" }
    $html = [string]$response.Content
    $pdfCandidate = Get-FirstRegexMatchValue -Text $html -Patterns @(
        'citation_pdf_url"\s+content="([^"]+)"',
        'href="([^"]+/pdf/[^"]+)"',
        "href='([^']+/pdf/[^']+)'"
    )

    if (-not $pdfCandidate) {
        throw "No se encontro PDF de PMC en '$ArticleUrl'."
    }

    return (Get-ResolvedUri -BaseUri $ArticleUrl -Candidate $pdfCandidate)
}

function Resolve-SourceUrl {
    param([Parameter(Mandatory = $true)][hashtable]$Item)

    switch ($Item.Method) {
        "direct" {
            return $Item.Source
        }
        "springer_doi" {
            return Resolve-SpringerPdfUrl -Doi $Item.Source
        }
        "figshare_article" {
            return Resolve-FigshareDownloadUrl -ArticleUrl $Item.Source
        }
        "html_first_pdf" {
            return Resolve-HtmlDownloadUrl -PageUrl $Item.Source
        }
        "pmc_article" {
            return Resolve-PmcPdfUrl -ArticleUrl $Item.Source
        }
        default {
            throw "Metodo de resolucion no soportado: $($Item.Method)"
        }
    }
}

function Download-ResearchItem {
    param([Parameter(Mandatory = $true)][hashtable]$Item)

    $destination = Join-Path $LibraryRoot $Item.Output
    $destinationDir = Split-Path -Parent $destination
    New-DirectoryIfMissing -Path $destinationDir

    if ((-not $ForceRedownload) -and (Test-IsPdfFile -Path $destination)) {
        return @{
            title = $Item.Title
            status = "skipped-existing"
            destination = $destination
            source = $Item.Source
            resolved_url = $null
            error = $null
        }
    }

    $resolvedUrl = $null
    $tempPath = $null

    try {
        $resolvedUrl = Resolve-SourceUrl -Item $Item
        $tempPath = "$destination.download"

        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }

        Invoke-WebRequestCompat `
            -Uri $resolvedUrl `
            -OutFile $tempPath `
            -MaximumRedirection 10 `
            -Headers @{ "User-Agent" = "Mozilla/5.0 SimufireResearchDownloader/1.0" }

        if (-not (Test-IsPdfFile -Path $tempPath)) {
            throw "La descarga no es un PDF valido."
        }

        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Force
        }

        Move-Item -LiteralPath $tempPath -Destination $destination

        return @{
            title = $Item.Title
            status = "downloaded"
            destination = $destination
            source = $Item.Source
            resolved_url = $resolvedUrl
            error = $null
        }
    }
    catch {
        if (($tempPath) -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force
        }

        return @{
            title = $Item.Title
            status = "failed"
            destination = $destination
            source = $Item.Source
            resolved_url = $resolvedUrl
            error = $_.Exception.Message
        }
    }
}

$items = @(
    @{ Title = "Occupant Tenability in Single Family Homes Part I"; Method = "direct"; Source = "https://fsri.org/sites/default/files/2021-07/Occupant_Tenability_in_Single_Family_Homes_Part_I.pdf"; Output = "FSRI_ULRI\\Occupant_Tenability_Part_I_2017.pdf" },
    @{ Title = "Occupant Tenability in Single Family Homes Part II"; Method = "direct"; Source = "https://fsri.org/sites/default/files/2021-07/Occupant_Tenability_in_Single_Family_Homes_Part_II.pdf"; Output = "FSRI_ULRI\\Occupant_Tenability_Part_II_2017.pdf" },
    @{ Title = "Effect of Firefighting Intervention on Occupant Tenability during a Residential Fire"; Method = "html_first_pdf"; Source = "https://link.springer.com/article/10.1007/s10694-019-00864-2"; Output = "Journals_OpenAccess\\Effect_of_Firefighting_Intervention_on_Occupant_Tenability_2019.pdf" },
    @{ Title = "Analysis of the Coordination of Suppression and Ventilation in Single-Family Homes"; Method = "html_first_pdf"; Source = "https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-single-family-homes"; Output = "FSRI_ULRI\\Coordination_Suppression_Ventilation_Single_Family_2020.pdf" },
    @{ Title = "Analysis of the Coordination of Suppression and Ventilation in Multi-Family Dwellings"; Method = "html_first_pdf"; Source = "https://fsri.org/resource/analysis-coordination-suppression-and-ventilation-multi-family-dwellings"; Output = "FSRI_ULRI\\Coordination_Suppression_Ventilation_Multi_Family_2020.pdf" },
    @{ Title = "Analysis of Search and Rescue Tactics in Single-Story Single-Family Homes Part III"; Method = "figshare_article"; Source = "https://ulri.figshare.com/articles/report/Analysis_of_Search_and_Rescue_Tactics_in_Single-Story_Single-Family_Homes_Part_III_Tactical_Considerations/28075001"; Output = "FSRI_ULRI\\Search_and_Rescue_Part_III_Tactical_Considerations.pdf" },
    @{ Title = "Impact of Ventilation on Fire Behavior in Legacy and Contemporary Residential Construction"; Method = "figshare_article"; Source = "https://ulri.figshare.com/articles/report/Impact_of_Ventilation_on_Fire_Behavior_in_Legacy_and_Contemporary_Residential_Construction/28087586"; Output = "FSRI_ULRI\\Impact_of_Ventilation_Legacy_and_Contemporary_Residential_Construction.pdf" },
    @{ Title = "Study of the Effectiveness of Fire Service Positive Pressure Ventilation During Fire Attack in Single Family Homes"; Method = "direct"; Source = "https://fsri.org/sites/default/files/2021-07/Positive_Pressure_Ventilation_Report_Website.pdf"; Output = "FSRI_ULRI\\Positive_Pressure_Ventilation_Report_2016.pdf" },
    @{ Title = "Understanding and Fighting Basement Fires"; Method = "figshare_article"; Source = "https://ulri.figshare.com/articles/report/Understanding_and_Fighting_Basement_Fires/28050134"; Output = "FSRI_ULRI\\Understanding_and_Fighting_Basement_Fires.pdf" },
    @{ Title = "Study of the Fire Service Training Environment: Safety, Fidelity, and Exposure - Acquired Structures"; Method = "figshare_article"; Source = "https://ulri.figshare.com/articles/report/Study_of_the_Fire_Service_Training_Environment_Safety_Fidelity_and_Exposure_-_Acquired_Structures/28083479"; Output = "FSRI_ULRI\\Study_of_the_Fire_Service_Training_Environment_Acquired_Structures.pdf" },
    @{ Title = "Impact of Fire Attack Utilizing Interior and Exterior Streams on Firefighter Safety and Occupant Survival: Full-Scale Experiments"; Method = "figshare_article"; Source = "https://ulri.figshare.com/articles/report/Impact_of_Fire_Attack_Utilizing_Interior_and_Exterior_Streams_on_Firefighter_Safety_and_Occupant_Survival_Full-Scale_Experiments/28084874"; Output = "FSRI_ULRI\\Impact_of_Fire_Attack_Full_Scale_Experiments.pdf" },
    @{ Title = "Residential Flashover Prevention with Reduced Water Flow: Phase 1"; Method = "figshare_article"; Source = "https://ulri.figshare.com/articles/report/Residential_Flashover_Prevention_with_Reduced_Water_Flow_Phase_1/28083218"; Output = "FSRI_ULRI\\Residential_Flashover_Prevention_Phase_1.pdf" },
    @{ Title = "Modeling Smoke Movement Through Compartmented Structures (NISTIR 4872)"; Method = "direct"; Source = "https://doi.org/10.6028/NIST.IR.4872"; Output = "NIST\\NISTIR_4872_Modeling_Smoke_Movement_Through_Compartmented_Structures.pdf" },
    @{ Title = "Improvement in Predicting Smoke Movement in Compartmented Structures"; Method = "direct"; Source = "https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=912721"; Output = "NIST\\Improvement_in_Predicting_Smoke_Movement_1993.pdf" },
    @{ Title = "Smoke Movement in Rooms of Fire Involvement and Adjacent Spaces"; Method = "direct"; Source = "https://doi.org/10.6028/NBS.IR.83-2748"; Output = "NIST\\NBS_IR_83_2748_Smoke_Movement_in_Rooms_and_Adjacent_Spaces.pdf" },
    @{ Title = "Carbon Monoxide Production in Compartment Fires: Full-Scale Enclosure Burns"; Method = "direct"; Source = "https://doi.org/10.6028/NIST.IR.5499"; Output = "NIST\\NISTIR_5499_Carbon_Monoxide_Production_Full_Scale.pdf" },
    @{ Title = "Experimental Study of the Effects of Fuel Type, Fuel Distribution, and Vent Size on Full-Scale Under-Ventilated Compartment Fires"; Method = "direct"; Source = "https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=861620"; Output = "NIST\\NIST_TN_1603_Underventilated_Compartment_Fires.pdf" },
    @{ Title = "Experimental Study of the Three Dimensional Internal Structure of Underventilated Compartment Fires"; Method = "direct"; Source = "https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=908944"; Output = "NIST\\NIST_TN_1736_Three_Dimensional_Internal_Structure.pdf" },
    @{ Title = "Propane Gas Fire Experiments in Residential Scale Structures"; Method = "direct"; Source = "https://doi.org/10.6028/NIST.TN.1953"; Output = "NIST\\NIST_TN_1953_Propane_Gas_Fire_Experiments_in_Residential_Scale_Structures.pdf" },
    @{ Title = "Report on Residential Fireground Field Experiments"; Method = "direct"; Source = "https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=904607"; Output = "NIST\\NIST_TN_1661_Residential_Fireground_Field_Experiments.pdf" },
    @{ Title = "Effects of HVAC on combustion-gas transport in residential structures"; Method = "html_first_pdf"; Source = "https://www.sciencedirect.com/science/article/pii/S0379711222000121"; Output = "Journals_OpenAccess\\Effects_of_HVAC_on_Combustion_Gas_Transport_2022.pdf" },
    @{ Title = "Experimental data from gas burner fires in residential structure with HVAC system"; Method = "pmc_article"; Source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC9792339/"; Output = "Journals_OpenAccess\\Experimental_Data_Gas_Burner_Fires_HVAC_2023.pdf" },
    @{ Title = "Numerical Simulations of Gas Burner Experiments in a Residential Structure with HVAC System"; Method = "springer_doi"; Source = "10.1007/s10694-023-01390-y"; Output = "Journals_OpenAccess\\Numerical_Simulations_Gas_Burner_Experiments_HVAC_2023.pdf" },
    @{ Title = "Analysis of Changing Residential Fire Dynamics and Its Implications on Firefighter Operational Timeframes"; Method = "springer_doi"; Source = "10.1007/s10694-011-0249-2"; Output = "Journals_OpenAccess\\Changing_Residential_Fire_Dynamics_2012.pdf" },
    @{ Title = "Air Moving Systems and Fire Protection"; Method = "direct"; Source = "https://doi.org/10.6028/NIST.IR.5227"; Output = "NIST\\NISTIR_5227_Air_Moving_Systems_and_Fire_Protection.pdf" },
    @{ Title = "Flow Induced by Fire in a Compartment"; Method = "direct"; Source = "https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=106938"; Output = "NIST\\Flow_Induced_by_Fire_in_a_Compartment_1982.pdf" },
    @{ Title = "CFAST - Consolidated Model of Fire Growth and Smoke Transport, Technical Reference Guide"; Method = "direct"; Source = "https://doi.org/10.6028/NIST.sp.1030"; Output = "Reviews_and_Models\\CFAST_Technical_Reference_Guide_2004.pdf" },
    @{ Title = "Impact of Fixed Ventilation on Fire Damage Patterns in Full-Scale Structures"; Method = "html_first_pdf"; Source = "https://ojp.gov/library/publications/impact-fixed-ventilation-fire-damage-patterns-full-scale-structures"; Output = "FSRI_ULRI\\Impact_of_Fixed_Ventilation_on_Fire_Damage_Patterns_2019.pdf" },
    @{ Title = "Evaluation of Heat Flux Profiles Through Walls in Support of Fire Model Validation"; Method = "direct"; Source = "https://www.ojp.gov/pdffiles1/nij/grants/309047.pdf"; Output = "FSRI_ULRI\\Evaluation_of_Heat_Flux_Profiles_Through_Walls_2024.pdf" },
    @{ Title = "Design Fire Characteristics for Probabilistic Assessments of Dwellings in England"; Method = "springer_doi"; Source = "10.1007/s10694-019-00925-6"; Output = "Journals_OpenAccess\\Design_Fire_Characteristics_for_Dwellings_2020.pdf" }
)

New-DirectoryIfMissing -Path $LibraryRoot

$results = foreach ($item in $items) {
    Write-Host "Descargando: $($item.Title)"
    $result = Download-ResearchItem -Item $item
    Start-Sleep -Milliseconds 250
    [PSCustomObject]$result
}

$manifestPath = Join-Path $LibraryRoot "download_manifest_fire_literature.json"
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$summary = $results | Group-Object -Property status | Sort-Object Name
Write-Host ""
Write-Host "Resumen:"
foreach ($entry in $summary) {
    Write-Host (" - {0}: {1}" -f $entry.Name, $entry.Count)
}
Write-Host ""
Write-Host "Manifest guardado en: $manifestPath"
