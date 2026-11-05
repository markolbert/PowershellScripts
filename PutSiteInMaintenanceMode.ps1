using module BlazorSites

param(
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -in [ModuleConfig]::BlazorSitesInfo.SitesInfo.Name })]
    [string]$ProjectName
)

$ErrorActionPreference = 'Stop'

$siteMgr = [BlazorSiteManagement]::new($ProjectName, "Development", $CsvDir)

$siteMgr.PutWebsiteInMaintenanceMode()
