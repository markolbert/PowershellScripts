using module BlazorSites

param(
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -in [ModuleConfig]::BlazorSitesInfo.SitesInfo.Name })]
    [string]$ProjectName,

    [Parameter(Mandatory)]
    [ValidateScript({
        if ($_ -in [ModuleConfig]::DbSources) { return $true }
        throw "Invalid DbSource '$_'. Valid values are: $([ModuleConfig]::DbSources -join ', ')"
    })]
    [string]$DbTarget,
    
    [string]$CsvDir
)

$ErrorActionPreference = 'Stop'

$siteMgr = [BlazorSiteManagement]::new($ProjectName, $DbTarget, $CsvDir)

$dbExists = Test-Path -LiteralPath $siteMgr.DatabasePath -PathType Leaf

if( $dbExists ){
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Update the database.')
        (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'No, cancel the update.')
    )

    # The last argument (1) sets the default index when pressing Enter (0 = Yes, 1 = No)
    $decision = $Host.UI.PromptForChoice('Confirm Action', "Do you want to update the $($siteMgr.DatabaseSource) database?", $choices, 1)

    if ($decision -eq 1) {
        return
    }
}

$siteMgr.UpdateDatabase()
