param(
    [Parameter(Mandatory)]
    [string]$RemoteFile,

    [Parameter(Mandatory)]
    [string]$LocalFile
)

$ErrorActionPreference = 'Stop'

$SftpHost = 'hwsrv-1339591.hostwindsdns.com'
$SftpUser = 'mark'
$SftpPort = 11921
$Key = Join-Path $HOME '.ssh\id_ed25519'

if (-not (Test-Path -LiteralPath $Key)) {
    throw "Private key not found: $Key"
}

$LocalFile = [IO.Path]::GetFullPath($LocalFile)
$LocalDir = Split-Path -Parent $LocalFile

if (-not (Test-Path -LiteralPath $LocalDir -PathType Container)) {
    throw "Windows destination folder does not exist: $LocalDir"
}

$service = Get-Service -Name ssh-agent

if ($service.Status -ne 'Running') {
    Start-Service ssh-agent
}

# Prompts for the private key's passphrase.
& ssh-add.exe $Key

if ($LASTEXITCODE -ne 0) {
    throw 'Could not load the SSH key into ssh-agent.'
}

$tempFile = "$LocalFile.$([guid]::NewGuid().ToString('N')).download"
$batchFile = Join-Path $env:TEMP "$([guid]::NewGuid().ToString('N')).sftp"
$remoteLocalPath = $tempFile.Replace('\', '/')
$batchLine = 'get "{0}" "{1}"' -f $RemoteFile, $remoteLocalPath

try {
    [IO.File]::WriteAllText(
        $batchFile,
        $batchLine + "`n",
        [Text.UTF8Encoding]::new($false)
    )

    & sftp.exe -P $SftpPort -i $Key -b $batchFile "$SftpUser@$SftpHost"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempFile)) {
        throw 'SFTP download failed; the existing Windows file was left unchanged.'
    }

    Move-Item -LiteralPath $tempFile -Destination $LocalFile -Force
    Write-Host "Downloaded $RemoteFile to $LocalFile"
}
finally {
    Remove-Item -LiteralPath $batchFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
}
