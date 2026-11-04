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
    [string]$DbSource,
    
    [string]$CsvDir
)

$ErrorActionPreference = 'Stop'

$siteMgr = [BlazorSiteManagement]::new($ProjectName, $DbSource, $CsvDir)

$dbExists = Test-Path -LiteralPath $siteMgr.DatabasePath -PathType Leaf

if( $siteMgr.DatabaseSource -eq 'Website' ){
    if( $dbExists ){
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Update the local copy.')
            (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Use the existing copy.')
        )

        # The last argument (1) sets the default index when pressing Enter (0 = Yes, 1 = No)
        $decision = $Host.UI.PromptForChoice('Confirm Action', 'Do you want to update the local copy of the site database?', $choices, 1)

        if ($decision -eq 0) {
            $dbExists = $false
        }
    }

    if( -not $dbExists ){
        $siteMgr.GrabSiteDatabase()
    }
}

$siteMgr.BackupDatabase()
