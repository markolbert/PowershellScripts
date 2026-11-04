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

# $SftpHost = 'hwsrv-1339591.hostwindsdns.com'
# $SftpPort = 11921

# # Relative to RemoteDir. These directories are deleted, then uploaded afresh.
# $RemoteDirsToDelete = @(
#     'wwwroot',
#     'Static'
# )

# # Relative to RemoteDir. Existing files are deleted before upload.
# $RemoteFilesToReplace = @(
#     "${EndpointsPrefix}.staticwebassets.endpoints.json",
#     $DbFile
# )

# $FoldersToUpload = @(
#     'publish/wwwroot',
#     'Static'
# )

# $FilesToUpload = @(
#     "publish/${EndpointsPrefix}.staticwebassets.endpoints.json",
#     $DBFile
# )

# # Check local upload sources before connecting or deleting anything.
# if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
#     throw "Local source directory not found: $ProjectDir"
# }

# foreach ($name in $FoldersToUpload) {
#     if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir $name) -PathType Container)) {
#         throw "Local folder not found: $(Join-Path $ProjectDir $name)"
#     }
# }

# foreach ($name in $FilesToUpload) {
#     if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir $name) -PathType Leaf)) {
#         throw "Local file not found: $(Join-Path $ProjectDir $name)"
#     }
# }

# # Prompts for root's VPS password; it is not stored in the script.
# $Credential = Get-Credential -UserName 'root' -Message 'Enter the VPS root password'

# function Quote-RemotePath([string]$Path) {
#     "'" + $Path.Replace("'", "'\''") + "'"
# }

# $RemoteRoot = $RemoteDir.TrimEnd('/')
# $DeletePaths = @()

# foreach ($name in $RemoteDirsToDelete + $RemoteFilesToReplace) {
#     $relative = $name.Replace('\', '/')
#     if ([string]::IsNullOrWhiteSpace($relative) -or
#         $relative.StartsWith('/') -or
#         $relative -match '(^|/)\.\.?(/|$)') {
#         throw "Use a safe relative path in the delete lists: $name"
#     }
#     $DeletePaths += "$RemoteRoot/$relative"
# }

# $sshSession = $null
# $sftpSession = $null

# try {
#     # -AcceptKey trusts a previously unseen server key. Verify the VPS host key
#     # fingerprint before the first run.
#     $sshSession = New-SSHSession -ComputerName $SftpHost -Port $SftpPort `
#         -Credential $Credential -AcceptKey
#     $sftpSession = New-SFTPSession -ComputerName $SftpHost -Port $SftpPort `
#         -Credential $Credential -AcceptKey

#     if ($DeletePaths.Count -gt 0) {
#         $confirmation = Read-Host 'Type DELETE to permanently remove the listed remote paths'
#         if ($confirmation -cne 'DELETE') {
#             throw 'Cancelled; no remote paths were deleted.'
#         }

#         $quotedPaths = ($DeletePaths | ForEach-Object {
#             Quote-RemotePath $_
#         }) -join ' '

#         $result = Invoke-SSHCommand -SessionId $sshSession.SessionId `
#             -Command "rm -rf -- $quotedPaths"

#         if ($result.ExitStatus -ne 0) {
#             throw "Remote deletion failed: $($result.Error -join ' ')"
#         }
#     }

#     foreach ($name in $FilesToUpload) {
#         Set-SFTPItem -SessionId $sftpSession.SessionId `
#             -Path (Join-Path $ProjectDir $name) `
#             -Destination "$RemoteRoot/$name" -Force
#     }

#     foreach ($name in $FoldersToUpload) {
#         Set-SFTPItem -SessionId $sftpSession.SessionId `
#             -Path (Join-Path $ProjectDir $name) `
#             -Destination "$RemoteRoot/$name" -Recurse -Force
#     }

#     Write-Host 'Upload completed.'
# }
# finally {
#     if ($sftpSession) {
#         Remove-SFTPSession -SessionId $sftpSession.SessionId | Out-Null
#     }
 
#     if ($sshSession) {
#         Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null
#     }
# }