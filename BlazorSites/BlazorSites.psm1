# common code for Blazor site database backup & load scripts

#region class definitions

class UpdatePathInfo {
    [string]$ProjectRelativePath
    [string]$RemoteRootRelativePath

    UpdatePathInfo([pscustomobject]$o) {
        $this.ProjectRelativePath = $o.ProjectRelativePath
        $this.RemoteRootRelativePath = $o.RemoteRootRelativePath
    }
}

class ApacheInfo {
    [string]$ConfigFile
    [string]$MaintenanceFile
    [string]$OnlineFile

    ApacheInfo([pscustomobject]$o){
        $this.ConfigFile = $o.ConfigFile
        $this.MaintenanceFile = $o.MaintenanceFile
        $this.OnlineFile = $o.OnlineFile
    }
}

class SiteInfo{
    [string]$Name
    [string]$ProjectPath
    [string]$DatabaseStub
    [string]$IdentityTable
    [string]$ServiceName
    [string]$RemoteSiteDirectory
    [ApacheInfo]$Apache
    [UpdatePathInfo[]]$DirectoriesToUpdate
    [UpdatePathInfo[]]$FilesToUpdate

    SiteInfo([pscustomobject]$o) {
        $this.Name = $o.Name
        $this.ProjectPath = $o.ProjectPath
        $this.DatabaseStub = $o.DatabaseStub
        $this.IdentityTable = $o.IdentityTable
        $this.ServiceName = $o.ServiceName
        $this.RemoteSiteDirectory = $o.RemoteSiteDirectory
        $this.DirectoriesToUpdate = $o.DirectoriesToUpdate | ForEach-Object { [UpdatePathInfo]::new($_) }
        $this.FilesToUpdate = $o.FilesToUpdate | ForEach-Object { [UpdatePathInfo]::new($_) }
        $this.Apache = [ApacheInfo]::new($o.Apache)
    }
}

class BlazorSitesInfo {
    [string]$HostName
    [int]$HostPort
    [string]$ApacheSiteDirectory
    [SiteInfo[]]$SitesInfo

    BlazorSitesInfo([pscustomobject]$o){
        $this.HostName = $o.HostName
        $this.HostPort = $o.HostPort
        $this.ApacheSiteDirectory = $o.ApacheSiteDirectory
        $this.SitesInfo = $o.Projects | ForEach-Object { [SiteInfo]::new($_) }
    }
}

class ModuleConfig{
    static [BlazorSitesInfo]$BlazorSitesInfo
    static [string[]]$DbSources = @('Development', 'Website')
}

class TableInfo {
    [string]$Name
    [string[]]$Columns

    TableInfo([string]$name, [string[]]$columns) {
        $this.Name = $name
        $this.Columns = $columns
    }
}

#endregion

#region module initialization code

$configPath = Join-Path $HOME 'Scripts/BlazorSites.json'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Configuration file not found: $configPath"
}

[ModuleConfig]::BlazorSitesInfo = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

#endregion

#region private helper functions (not exported)

function Convert-ToQuotedPath([string]$Path) {
    "'" + $Path.Replace("'", "'\''") + "'"
}

function Resolve-PathText([string]$path) {
    if ([IO.Path]::IsPathRooted($path)) {
        return [IO.Path]::GetFullPath($path)
    }

    return [IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $path))
}

function Convert-SqlIdentifier([string]$name) {
    return '"' + $name.Replace('"', '""') + '"'
}

function Convert-SqlStringLiteral([string]$value) {
    return "'" + $value.Replace("'", "''") + "'"
}

function GetTableInfo( [object]$siteMgr ) {
    if( $null -eq $siteMgr.ProjectName ){
        throw "ProjectName is not defined or empty"
    }

    $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $siteMgr.ProjectName }
    if( $null -eq $site ){
        throw "Unknown project: $(siteMgr.ProjectName)"
    }

    $tableInfoPath = Join-Path $site.ProjectPath 'TableDetails.json'

    if (-not (Test-Path -LiteralPath $tableInfoPath -PathType Leaf)) {
        throw "Table Info file not found: $tableInfoPath"
    }

    $json = Get-Content -LiteralPath $tableInfoPath -Raw | ConvertFrom-Json

    return @(
        foreach ($entry in $json) {
            [TableInfo]::new($entry.Name, [string[]]$entry.Columns)
        })
}

function SetProjectPath([object] $siteMgr, [string] $name ) {
    if( [string]::IsNullOrEmpty($name) ){
        throw 'Undefined project name!'
    }

    $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $name }
    if( $null -eq $site ){
        throw "Unknown project: $name"
    }

    $siteMgr.ProjectPath = $site.ProjectPath
    $siteMgr.ProjectName = $name
}

function SetDbPath( [object]$siteMgr, [string]$dbSrc ){
    if( [string]::IsNullOrEmpty($siteMgr.ProjectPath) ){
        throw 'Undefined project path!'
    }

    $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $siteMgr.ProjectName }
    if( $null -eq $site ){
        throw "Unknown project: $($siteMgr.ProjectName)"
    }

    $dbStub = $site.DatabaseStub

    switch( $dbSrc ){
        'Development' { $siteMgr.DatabasePath = Join-Path $siteMgr.ProjectPath "${dbStub}.db" }
        'Website' { $siteMgr.DatabasePath = Join-Path $siteMgr.ExeDir "${dbStub}-site.db" }
        
        default { throw "Invalid database source: $dbSrc" }
    }

    $siteMgr.DatabaseSource = $dbSrc
}

function SetCsvPath( [object]$siteMgr, [string]$dir ) {
    if([string]::IsNullOrEmpty($dir)){
        $tempDir = $null

        if( [string]::IsNullOrEmpty($siteMgr.DatabaseSource)){
            throw 'Cannot determine Csv path because DatabaseSource is undefined or empty'
        }

        switch( $siteMgr.DatabaseSource ){
            'Development' { $tempDir = 'fromdev' }
            'Website' { $tempDir = 'fromsite' }
            default { throw "Invalid database source: $($siteMgr.DatabaseSource)" }
        }
    }
    else {
        $tempDir = $dir
    }

    $siteMgr.CsvPath = Resolve-PathText($tempDir)

    New-Item -Path $siteMgr.CsvPath -ItemType Directory -Force

    if (-not (Test-Path -LiteralPath $siteMgr.CsvPath -PathType Container)) {
        throw "Csv directory not found: $($siteMgr.CsvPath)"
    }
}

#endregion

class BlazorSiteManagement {
    [string]$ProjectName = $null
    [string]$ProjectPath = $null
    [string]$DatabaseSource = $null
    [string]$DatabasePath = $null
    [string]$CsvPath = $null
    [string]$ExeDir = $null
    [PSCustomObject]$SshSession = $null
    [PSCustomObject]$SftpSession = $null

    BlazorSiteManagement( 
        [string]$projName, 
        [string]$dbSource, 
        [string]$csvDir = $null)
        {
            $this.ExeDir = [IO.Path]::GetFullPath((Get-Location).Path)
            SetProjectPath $this $projName
            SetDbPath $this $dbSource
            SetCsvPath $this $csvDir
        }

    [bool] GrabSiteDatabase() {
        if( $null -eq $this.ProjectName ){
            throw "ProjectName is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        $dbStub = $site.DatabaseStub

        $remotePath = "$($site.RemoteSiteDirectory)/${dbStub}.db"
        $localPath = Join-Path $this.ExeDir "${dbStub}-site.db"

        $remoteHost = [ModuleConfig]::BlazorSitesInfo.HostName

        scp -i "$env:USERPROFILE\.ssh\id_ed25519" -P ([ModuleConfig]::BlazorSitesInfo.HostPort) `
            "mark@${remoteHost}:${remotePath}" $localPath

        if( $LASTEXITCODE -eq 0 ){
            return $true
        }

        Write-Host "Could not grab data from $remotePath"
        return $false
    }

    [void] BackupDatabase(){
        if( $null -eq $this.DatabasePath ){
            throw "DatabasePath is not defined or empty"
        }

        if( $null -eq $this.CsvPath ){
            throw "CsvPath is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        $sqlite = (Get-Command sqlite3.exe -ErrorAction Stop).Source

        $tableInfo = GetTableInfo( $this )

        New-Item -ItemType Directory -Path $this.CsvPath -Force

        foreach ($table in $tableInfo) {
            $curPath = Join-Path $this.CsvPath "$($table.Name).csv"

            $nameLiteral = Convert-SqlStringLiteral($table.Name)
            $checkSql = "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name=$nameLiteral);"
            $exists = (& $sqlite $this.DatabasePath $checkSql).Trim()

            if( $exists -ne "1" ){
                if (Test-Path -LiteralPath $curPath -PathType Leaf) {
                    Remove-Item -LiteralPath $curPath -Force
                    Write-Host "$($table.Name) is missing; deleted its CSV output."
                } 
                else {
                    Write-Host "$($table.Name) is missing; no CSV to delete."
                }
            
                continue;
            }

            Write-Host "Exporting table $($table.Name) to $($curPath)"

            $outputCommand = '.output "{0}"' -f $curPath.Replace('\', '/')

            $quotedTable = Convert-SqlIdentifier($table.Name)

            $output = & $sqlite $this.DatabasePath '.headers on' `
                '.mode csv' $outputCommand "SELECT * FROM $quotedTable;" 2>&1

            $exitCode = $LASTEXITCODE  # save this immediately

            if ($exitCode -ne 0) {
                Write-Host "sqlite exit code: $exitCode"
                Write-Host $output

                throw "Export failed for table $table (sqlite3 exit code $LASTEXITCODE)."
            }
        }

        Write-Host "Done. CSV files are in $($this.CsvPath)"    
    }

    [void] UpdateDatabase(){
        if( $null -eq $this.ProjectName ){
            throw "ProjectName is not defined or empty"
        }

        if( $null -eq $this.DatabasePath ){
            throw "DatabasePath is not defined or empty"
        }

        if( $null -eq $this.CsvPath ){
            throw "CsvPath is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        $sqlite = (Get-Command sqlite3.exe -ErrorAction Stop).Source

        $tableInfo = GetTableInfo( $this )

        $staged = @()

        try {
            foreach ($item in $tableInfo) {
                $curPath = Join-Path $this.CsvPath "$($item.Name).csv"

                if (-not (Test-Path -LiteralPath $curPath -PathType Leaf)) {
                    Write-Host "[SKIP] `"$curPath`" not found - $($item.Name) not touched."
                    continue
                }

                if ((Get-Item -LiteralPath $curPath).Length -eq 0) {
                    Write-Host "Skipping empty file: $curPath"
                    continue
                }

                $stageTable = "_import_$($item.Name)"
                $quotedStage = Convert-SqlIdentifier($stageTable)

                # Register it first so cleanup also handles a failed import.
                $staged += [pscustomobject]@{
                    Table = $item.Name
                    Stage = $stageTable
                    Columns = $item.Columns
                }

                & $sqlite -bail $this.DatabasePath "DROP TABLE IF EXISTS $quotedStage;"
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not prepare staging table for $($item.Name)."
                }

                Write-Host "Importing $($curPath) into staging table"

                # Import into a staging table; the CSV path is quoted for spaces.
                $modCsvPath =  $curPath.Replace('\', '/')
                $importCommand = '.import "{0}" {1}' -f $modCsvPath, $stageTable

                $output = & $sqlite -echo -bail $this.DatabasePath '.mode csv' $importCommand 2>&1
                $exitCode = $LASTEXITCODE  # save this immediately

                if ($exitCode -ne 0) {
                    Write-Host "sqlite exit code: $exitCode"
                    Write-Host $output

                    throw "CSV import failed for $curPath."
                }
            }

            Write-Host 'Preparing table updates'

            # Replace the destination tables together in one transaction.
            $sqlLines = @('BEGIN IMMEDIATE;')

            foreach ($item in $staged) {
                Write-Host "Creating instructions to import staging table into $($item.Table)"

                $target = Convert-SqlIdentifier($item.Table)
                $stage = Convert-SqlIdentifier($item.Stage)
                $columns = ($item.Columns | ForEach-Object { Convert-SqlIdentifier $_ }) -join ', '

                $sqlLines += "DELETE FROM $target;"
                $sqlLines += "INSERT INTO $target ($columns) SELECT $columns FROM $stage;"
                $sqlLines += "DROP TABLE $stage;"
            }

            Write-Host "Adding update of LockoutEnd field to Null in $($site.IdentityTable)"

            $identityTable = Convert-SqlIdentifier($site.IdentityTable)
            $sqlLines += "UPDATE $identityTable SET `"LockoutEnd`" = NULL;"
            $sqlLines += 'COMMIT;'

            Write-Host 'Executing table updates'

            $output = & $sqlite -echo -bail $this.DatabasePath ($sqlLines -join "`n") 2>&1
            $exitCode = $LASTEXITCODE  # save this immediately

            if ($LASTEXITCODE -ne 0) {
                Write-Host "sqlite exit code: $exitCode"
                Write-Host $output

                throw 'Database import transaction failed.'
            }

            Write-Host 'Done.'
        }
        finally {
            # Remove leftover staging tables if an import or transaction failed.
            if ($staged.Count -gt 0) {
                $cleanup = ($staged | ForEach-Object {
                    'DROP TABLE IF EXISTS {0};' -f (Convert-SqlIdentifier $_.Stage)
                }) -join "`n"

                & $sqlite -bail $this.DatabasePath $cleanup *> $null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning 'Could not remove one or more temporary staging tables.'
                }
            }
        }
    }

    [void] InitRemoteAccess() {
        $credential = Get-Credential -UserName 'root' -Message 'Enter passphrase for identity file'

        $hostName = [ModuleConfig]::BlazorSitesInfo.HostName
        $hostPort =[ModuleConfig]::BlazorSitesInfo.HostPort

        Write-Host 'Starting SSH session'

        $this.SshSession = New-SSHSession -ComputerName $hostName -Port $hostPort `
            -Credential $credential `
            -KeyFile "$env:USERPROFILE\.ssh\id_ed25519" -AcceptKey

        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "Establishing new SSH session failed with exit code $exitCode."
        }

        Write-Host 'Starting SFTP session'

        $this.SftpSession = New-SFTPSession -ComputerName $hostName -Port $hostPort `
            -Credential $credential `
            -KeyFile "$env:USERPROFILE\.ssh\id_ed25519"  -AcceptKey

        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw "Establishing new SFTP session failed with exit code $exitCode."
        }
    }

    [void] EndRemoteAccess(){
        if ($this.SftpSession) {
            Write-Host 'Ending SFTP session'

            Remove-SFTPSession -SessionId $this.SftpSession.SessionId
            $this.SftpSession = $null
        }
    
        if ($this.SshSession) {
            Write-Host 'Ending SSH session'
            
            Remove-SSHSession -SessionId $this.SshSession.SessionId
            $this.SshSession = $null
        }
    }
    
    [void] ExecuteSSHCommand([string]$command, [string] $mesg){
        if( $null -eq $this.SshSession ){
            $this.InitRemoteAccess()
        }

        $result = Invoke-SSHCommand -SessionId $this.SshSession.SessionId `
            -Command $command

        if( [string]::IsNullOrEmpty($mesg)) {
            $mesg = "$command failed"
        }

        if ($result.ExitStatus -ne 0) {
            throw "${mesg}: $($result.Error -join ' ')"
        }
    }

    [void] PutWebsiteInMaintenanceMode(){
        if( $null -eq $this.ProjectName ){
            throw "ProjectName is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }

        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        Write-Host "Putting $site.ServiceName into maintenance mode"

        $siteDir = [ModuleConfig]::BlazorSitesInfo.ApacheSiteDirectory.TrimEnd('/')

        $cmd = "sudo sed -i.bak 's|^[[:space:]]*include $($siteDir)/$($site.Apache.OnlineFile)$|    include $($siteDir)/$($site.Apache.MaintenanceFile)|' $($siteDir)/$($site.Apache.ConfigFile)"
        $this.ExecuteSSHCommand($cmd, 'Switch to maintenance mode failed')

        Write-Host 'Shutting down site'
        
        $this.ExecuteSSHCommand("systemctl stop $($site.ServiceName)", 'Stopping service failed')

        Write-Host 'Reloading apache'
        
        $this.ExecuteSSHCommand('systemctl reload apache2', 'Reloading apache2 failed')
    }

    [void] RestartWebsite(){
        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }

        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        Write-Host "Restarting $site.ServiceName"

        $this.ExecuteSSHCommand("systemctl restart $($site.ServiceName)", 'Stopping service failed')

        Write-Host 'Taking site out of maintenance mode.'
        
        $siteDir = [ModuleConfig]::BlazorSitesInfo.ApacheSiteDirectory.TrimEnd('/')

        $cmd = "sudo sed -i.bak 's|^[[:space:]]*include $($siteDir)/$($site.Apache.MaintenanceFile)$|    include $($siteDir)/$($site.Apache.OnlineFile)|' $($siteDir)/$($site.Apache.ConfigFile)"
        $this.ExecuteSSHCommand($cmd, 'Failed to exit maintenance mode' )

        Write-Host 'Reloading apache'
        
        $this.ExecuteSSHCommand('systemctl reload apache2', 'Reloading apache2 failed')
    }

    [void] PublishToWebsite() {
        if( $null -eq $this.ProjectName ){
            throw "ProjectName is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        Write-Host 'Publishing development source code'

        dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o ./publish
        $publishExitCode = $LASTEXITCODE

        if ($publishExitCode -ne 0) {
            throw "dotnet publish failed with exit code $publishExitCode."
        }

        Write-Host 'Identifying directories and files to update on the server'

        foreach( $pathInfo in $site.DirectoriesToUpdate ){
            $path = Join-Path $site.ProjectPath $pathInfo.ProjectRelativePath

            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw "Missing directory: $path"
            }
        }

        foreach( $pathInfo in $site.FilesToUpdate ){
            $path = Join-Path $site.ProjectPath $pathInfo.ProjectRelativePath

            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing file: $path"
            }
        }

        $remoteRoot = $site.RemoteSiteDirectory.TrimEnd('/')
        $deletePaths = @()

        foreach ($path in $site.DirectoriesToUpdate + $site.FilesToUpdate) {
            $relative = $path.RemoteRootRelativePath

            if ([string]::IsNullOrWhiteSpace($relative) -or
                $relative.StartsWith('/') -or
                $relative -match '(^|/)\.\.?(/|$)') {
                throw "Use a safe relative path in the delete lists: $site.Name"
            }

            $deletePaths += "$remoteRoot/$relative"
        }

        try {
            $this.PutWebsiteInMaintenanceMode()

            $quotedPaths = ($DeletePaths | ForEach-Object {
                Convert-ToQuotedPath( $_ )
            }) -join ' '

            Write-Host 'Removing files and directories to be replaced'
            
            $this.ExecuteSSHCommand("rm -rf -- $quotedPaths", 'Removing files and directories failed')

            Write-Host 'Uploading replacement files'

            foreach ($fileInfo in $site.FilesToUpdate) {
                $localFilePath = Join-Path $this.ProjectPath $fileInfo.ProjectRelativePath

                Set-SFTPItem -SessionId $this.SftpSession.SessionId -Path $localFilePath `
                    -Destination $site.RemoteSiteDirectory -Force
            }

            Write-Host 'Uploading replacement directories'

            foreach ($dirInfo in $site.DirectoriesToUpdate) {
                $localDirPath = Join-Path $this.ProjectPath $dirInfo.ProjectRelativePath

                Set-SFTPItem -SessionId $this.SftpSession.SessionId -Path $localDirPath `
                    -Destination $site.RemoteSiteDirectory -Force
            }

            Write-Host 'Updating file and directory ownership'
            
            $this.ExecuteSSHCommand("cd -- '$($site.RemoteSiteDirectory)' && chown -R www-data:www-data -- *", 'Updating ownership failed')

            Write-Host 'Making DLL executable'
            
            $this.ExecuteSSHCommand("cd -- '$($site.RemoteSiteDirectory)' && chmod u+x $($site.Name)", 'Changing executability failed')

            Write-Host 'Upload completed.'

            $this.RestartWebsite()
            
            Write-Host 'Done'
        }
        finally {
            $this.EndRemoteAccess()
        }    
    }
}

Export-ModuleMember -Function @()