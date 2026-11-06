# Signs Windows binaries with a PFX code-signing certificate via signtool.
#
# Used by .github/workflows/build-windows.yml when the WINDOWS_CERT_PFX_BASE64
# and WINDOWS_CERT_PASSWORD secrets are set. Azure Artifact Signing is handled
# by its own action in the workflow and does not use this script.

param(
    [Parameter(Mandatory = $true)][string[]]$Files,
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

if (-not $env:WINDOWS_CERT_PFX_BASE64 -or -not $env:WINDOWS_CERT_PASSWORD) {
    throw "WINDOWS_CERT_PFX_BASE64 and WINDOWS_CERT_PASSWORD must both be set."
}

$signtool = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $signtool) { throw "signtool.exe was not found in the Windows SDK." }

$pfxPath = Join-Path $env:RUNNER_TEMP "cookie-signing.pfx"
[IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($env:WINDOWS_CERT_PFX_BASE64))

try {
    foreach ($file in $Files) {
        & $signtool.FullName sign /f $pfxPath /p $env:WINDOWS_CERT_PASSWORD `
            /fd SHA256 /tr $TimestampUrl /td SHA256 /d "Cookie" $file
        if ($LASTEXITCODE -ne 0) { throw "signtool failed to sign $file" }

        & $signtool.FullName verify /pa /v $file
        if ($LASTEXITCODE -ne 0) { throw "Signature verification failed for $file" }
    }
}
finally {
    Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue
}
