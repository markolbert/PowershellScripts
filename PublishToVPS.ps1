using module BlazorSites

param(
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -in [ModuleConfig]::BlazorSitesInfo.SitesInfo.Name })]
    [string]$ProjectName
)

$ErrorActionPreference = 'Stop'

$siteMgr = [BlazorSiteManagement]::new($ProjectName, "Development", $CsvDir)

$choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
    (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'The server is shut down.')
    (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'No, cancel the publish operation.')
)

# The last argument (1) sets the default index when pressing Enter (0 = Yes, 1 = No)
$decision = $Host.UI.PromptForChoice('Confirm Action', "Is the remote server ready to be updated?", $choices, 1)

if ($decision -eq 1) {
    return
}

$siteMgr.PublishToWebsite()
