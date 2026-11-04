# common code for Blazor site database backup & load scripts
class UpdatePathInfo {
    [string]$ProjectRelativePath
    [string]$RemoteRootRelativePath

    UpdatePathInfo([pscustomobject]$o) {
        $this.ProjectRelativePath = $o.ProjectRelativePath
        $this.RemoteRootRelativePath = $o.RemoteRootRelativePath
    }
}

class SiteInfo{
    [string]$Name
    [string]$ProjectPath
    [string]$DatabaseStub
    [string]$RemoteSiteDirectory
    [UpdatePathInfo[]]$DirectoriesToUpdate
    [UpdatePathInfo[]]$FilesToUpdate

    SiteInfo([pscustomobject]$o) {
        $this.Name = $o.Name
        $this.ProjectPath = $o.ProjectPath
        $this.DatabaseStub = $o.DatabaseStub
        $this.RemoteSiteDirectory = $o.RemoteSiteDirectory
        $this.DirectoriesToUpdate = $o.DirectoriesToUpdate | ForEach-Object { [UpdatePathInfo]::new($_) }
        $this.FilesToUpdate = $o.FilesToUpdate | ForEach-Object { [UpdatePathInfo]::new($_) }
    }
}

class BlazorSitesInfo {
    [string]$HostName
    [int]$HostPort
    [SiteInfo[]]$SitesInfo

    BlazorSitesInfo([pscustomobject]$o){
        $this.HostName = $o.HostName
        $this.HostPort = $o.HostPort
        $this.SitesInfo = $o.Projects | ForEach-Object { [SiteInfo]::new($_) }
    }
}

class ModuleConfig{
    static [BlazorSitesInfo]$BlazorSitesInfo
    static [string[]]$DbSources = @('Development', 'Website')
}

$configPath = Join-Path $HOME 'Scripts/BlazorSites.json'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Configuration file not found: $configPath"
}

[ModuleConfig]::BlazorSitesInfo = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

class TableInfo {
    [string]$Name
    [string[]]$Columns

    TableInfo([string]$name, [string[]]$columns) {
        $this.Name = $name
        $this.Columns = $columns
    }
}

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

class BlazorSiteManagement {
    [string]$ProjectName = $null
    [string]$ProjectPath = $null
    [string]$DatabaseSource = $null
    [string]$DatabasePath = $null
    [string]$CsvPath = $null
    [string]$ExeDir = $null

    BlazorSiteManagement( 
        [string]$projName, 
        [string]$dbSource, 
        [string]$csvDir = $null)
        {
            $this.ExeDir = [IO.Path]::GetFullPath((Get-Location).Path)
            $this.SetProjectPath($projName)
            $this.SetDbPath($dbSource)
            $this.SetCsvPath($csvDir)
        }

    [void] SetProjectPath( [string] $name ){
        if( [string]::IsNullOrEmpty($name) ){
            throw 'Undefined project name!'
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $name }
        if( $null -eq $site ){
            throw "Unknown project: $name"
        }

        $this.ProjectPath = $site.ProjectPath
        $this.ProjectName = $name
    }

    [void] SetDbPath( [string]$dbSrc ){
        if( [string]::IsNullOrEmpty($this.ProjectPath) ){
            throw 'Undefined project path!'
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        $dbStub = $site.DatabaseStub

        switch( $dbSrc ){
            'Development' { $this.DatabasePath = Join-Path $this.ProjectPath "${dbStub}.db" }
            'Website' { $this.DatabasePath = Join-Path $this.ExeDir "${dbStub}-site.db" }
            
            default { throw "Invalid database source: $dbSrc" }
        }

        $this.DatabaseSource = $dbSrc
    }

    [void] SetCsvPath([string]$dir){
        if([string]::IsNullOrEmpty($dir)){
            $tempDir = $null

            if( [string]::IsNullOrEmpty($this.DatabaseSource)){
                throw 'Cannot determine Csv path because DatabaseSource is undefined or empty'
            }

            switch( $this.DatabaseSource ){
                'Development' { $tempDir = 'fromdev' }
                'Website' { $tempDir = 'fromsite' }
                default { throw "Invalid database source: $(this.DatabaseSource)" }
            }
        }
        else {
            $tempDir = $dir
        }

        $this.CsvPath = Resolve-PathText($tempDir)

        New-Item -Path $this.CsvPath -ItemType Directory -Force

        if (-not (Test-Path -LiteralPath $this.CsvPath -PathType Container)) {
            throw "Csv directory not found: $($this.CsvPath)"
        }
    }

    [TableInfo[]] GetTableInfo(){
        if( $null -eq $this.ProjectName ){
            throw "ProjectName is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
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

        # scp -i "$env:USERPROFILE\.ssh\id_ed25519" -P 11921 "mark@hwsrv-1339591.hostwindsdns.com:$remotePath" $localPath
        $remoteHost = [ModuleConfig]::BlazorSitesInfo.HostName

        scp -i "$env:USERPROFILE\.ssh\id_ed25519" -P ([ModuleConfig]::BlazorSitesInfo.HostPort) "mark@${remoteHost}:${remotePath}" $localPath

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

        $tableInfo = $this.GetTableInfo()

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

            $outputCommand = '.output "{0}"' -f $curPath.Replace('\', '/')

            $quotedTable = Convert-SqlIdentifier($table.Name)

            $output = & $sqlite $this.DatabasePath '.headers on' '.mode csv' $outputCommand "SELECT * FROM $quotedTable;" 2>&1
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

        $tableInfo = $this.GetTableInfo()

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

            # Replace the destination tables together in one transaction.
            $sqlLines = @('BEGIN IMMEDIATE;')

            foreach ($item in $staged) {
                $target = Convert-SqlIdentifier($item.Table)
                $stage = Convert-SqlIdentifier($item.Stage)
                $columns = ($item.Columns | ForEach-Object { Convert-SqlIdentifier $_ }) -join ', '

                $sqlLines += "DELETE FROM $target;"
                $sqlLines += "INSERT INTO $target ($columns) SELECT $columns FROM $stage;"
                $sqlLines += "DROP TABLE $stage;"
            }

            $sqlLines += 'UPDATE "Members" SET "LockoutEnd" = NULL;'
            $sqlLines += 'COMMIT;'

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

    [void] PublishToWebsite() {
        if( $null -eq $this.ProjectName ){
            throw "ProjectName is not defined or empty"
        }

        $site = [ModuleConfig]::BlazorSitesInfo.SitesInfo | Where-Object { $_.Name -eq $this.ProjectName }
        if( $null -eq $site ){
            throw "Unknown project: $(this.ProjectName)"
        }

        dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o ./publish
        $publishExitCode = $LASTEXITCODE

        if ($publishExitCode -ne 0) {
            throw "dotnet publish failed with exit code $publishExitCode."
        }

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

        # Prompts for root's VPS password; it is not stored in the script.
        # We use this weird workaround because VsCode Terminal does not
        # reliably handle Ctrl-V pasted text. Thanx, Microsoft :( !
        Write-Host "Copy the VPS root password to the clipboard, then return here." -ForegroundColor Yellow
        $null = Read-Host "Press ENTER when the password is in the clipboard"

        $plainPassword = (Get-Clipboard -Raw).Trim()
        $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
        $credential = [pscredential]::new('root', $securePassword)

        Remove-Variable plainPassword, securePassword
        Set-Clipboard -Value ''

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

        $sshSession = $null
        $sftpSession = $null
        $hostName = [ModuleConfig]::BlazorSitesInfo.HostName
        $hostPort =[ModuleConfig]::BlazorSitesInfo.HostPort

        try {
            # -AcceptKey trusts a previously unseen server key. Verify the VPS host key
            # fingerprint before the first run.
            $sshSession = New-SSHSession -ComputerName $hostName -Port $hostPort -Credential $credential -AcceptKey

            $sessionExitCode = $LASTEXITCODE

            if ($sessionExitCode -ne 0) {
                throw "Establishing new SSH session failed with exit code $sessionExitCode."
            }

            $sftpSession = New-SFTPSession -ComputerName $hostName -Port $hostPort -Credential $credential -AcceptKey

            $ftpExitCode = $LASTEXITCODE

            if ($ftpExitCode -ne 0) {
                throw "Establishing new SFTP session failed with exit code $ftpExitCode."
            }

            $quotedPaths = ($DeletePaths | ForEach-Object {
                Convert-ToQuotedPath( $_ )
            }) -join ' '

            $result = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command "rm -rf -- $quotedPaths"

            if ($result.ExitStatus -ne 0) {
                throw "Remote deletion failed: $($result.Error -join ' ')"
            }

            foreach ($fileInfo in $site.FilesToUpdate) {
                $localFilePath = Join-Path $this.ProjectPath $fileInfo.ProjectRelativePath

                Set-SFTPItem -SessionId $sftpSession.SessionId -Path $localFilePath -Destination $site.RemoteSiteDirectory -Force
            }

            foreach ($dirInfo in $site.DirectoriesToUpdate) {
                $localDirPath = Join-Path $this.ProjectPath $dirInfo.ProjectRelativePath

                Set-SFTPItem -SessionId $sftpSession.SessionId -Path $localDirPath -Destination $site.RemoteSiteDirectory -Force
            }

            $result = Invoke-SSHCommand -SessionId $sshSession.SessionId `
                -Command "cd -- '$($site.RemoteSiteDirectory)' && chown -R www-data:www-data -- *"

            if ($result.ExitStatus -ne 0) {
                throw "Could not chown files and directories: $($result.Error -join ' ')"
            }

            $result = Invoke-SSHCommand -SessionId $sshSession.SessionId `
                -Command "cd -- '$($site.RemoteSiteDirectory)' && chmod u+x $($site.Name)"

            if ($result.ExitStatus -ne 0) {
                throw "Could not chmod $site.Name: $($result.Error -join ' ')"
            }

            Write-Host 'Upload completed.'
        }
        finally {
            if ($sftpSession) {
                Remove-SFTPSession -SessionId $sftpSession.SessionId
            }
        
            if ($sshSession) {
                Remove-SSHSession -SessionId $sshSession.SessionId
            }
        }    
    }
}
