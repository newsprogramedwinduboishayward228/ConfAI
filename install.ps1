<#
.SYNOPSIS
    Installs ConfAI, the CLI for every AI coding agent's config.

.DESCRIPTION
    Downloads the release archive for this machine's architecture, verifies it
    against the SHA256SUMS file published with the release, and installs the
    binary. A checksum mismatch aborts before anything is written.

    Running a script downloaded from the internet is a trust decision. Read it
    first if you would rather not take it on faith; INSTALL.md documents the
    archive and `cargo install` routes, which do not involve this file.

    Works on Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
    irm https://raw.githubusercontent.com/redstone-md/ConfAI/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Version v0.0.1 -Prefix C:\tools\confai

.EXAMPLE
    .\install.ps1 -Uninstall
#>

[CmdletBinding()]
param(
    [string] $Version,
    [string] $Prefix,
    [switch] $NoModifyPath,
    [switch] $Force,
    [switch] $Quiet,
    [switch] $Uninstall
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Invoke-WebRequest's progress bar makes downloads several times slower in
# Windows PowerShell, and there is nothing useful in it here.
$ProgressPreference = 'SilentlyContinue'

$Repo = 'redstone-md/ConfAI'
$BinName = 'confai'
$ExeName = 'confai.exe'

function Write-Info {
    param([string] $Message)
    if (-not $Quiet) { Write-Host $Message }
}

function Write-Fail {
    param([string] $Message)
    throw $Message
}

function Get-TargetTriple {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }

    switch ($arch) {
        'AMD64' { return 'x86_64-pc-windows-msvc' }
        'ARM64' { return 'aarch64-pc-windows-msvc' }
        'x86' {
            Write-Fail '32-bit Windows is not published. Build from source with: cargo install confai'
        }
        default {
            Write-Fail "Unsupported architecture: $arch"
        }
    }
}

function Initialize-Tls {
    # Windows PowerShell 5.1 can still default to TLS 1.0, which GitHub refuses.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        } catch {
            Write-Verbose 'Could not raise the TLS version; continuing.'
        }
    }
}

function Resolve-LatestTag {
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'confai-installer' }
    } catch {
        Write-Fail "Could not reach the GitHub API ($url). Pass -Version vX.Y.Z to skip the lookup. $($_.Exception.Message)"
    }
    # Strict mode turns a missing property into an exception, so ask whether it
    # exists rather than reading it and hoping.
    $prop = $release.PSObject.Properties['tag_name']
    if ((-not $prop) -or (-not $prop.Value)) {
        Write-Fail 'The GitHub API response had no tag_name. Pass -Version vX.Y.Z.'
    }
    return $prop.Value
}

function Get-ExpectedHash {
    param(
        [string] $SumsPath,
        [string] $FileName
    )

    foreach ($line in (Get-Content -LiteralPath $SumsPath)) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        # `sha256sum` writes "<hash>  <name>", sometimes with a leading '*'.
        $parts = $trimmed -split '\s+', 2
        if ($parts.Count -lt 2) { continue }
        $name = $parts[1].Trim().TrimStart('*')
        if ($name -eq $FileName) { return $parts[0].Trim() }
    }
    return $null
}

function Get-UserPathEntries {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { return @() }
    return @($current -split ';' | Where-Object { $_ -ne '' })
}

function Test-PathContains {
    param([string] $Directory)

    $wanted = $Directory.TrimEnd('\')
    foreach ($entry in (Get-UserPathEntries)) {
        if ($entry.TrimEnd('\') -ieq $wanted) { return $true }
    }
    return $false
}

# The user PATH only. Writing the machine PATH needs elevation and affects
# everyone on the box, which is not this installer's business.
function Add-ToUserPath {
    param([string] $Directory)

    if (Test-PathContains -Directory $Directory) {
        Write-Info "PATH already contains $Directory."
        return
    }

    if ($NoModifyPath) {
        Write-Warning "$Directory is not on your PATH, and -NoModifyPath was given."
        Write-Warning "Add it yourself, or run $BinName by its full path."
        return
    }

    $entries = Get-UserPathEntries
    $entries += $Directory
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')

    # So the rest of this session can find it without a restart.
    $env:Path = "$env:Path;$Directory"

    Write-Info ''
    Write-Info "Added to your user PATH: $Directory"
    Write-Info 'To undo, run:  .\install.ps1 -Uninstall'
    Write-Warning 'Already-open terminals keep the old PATH. Open a new one.'
}

function Remove-FromUserPath {
    param([string] $Directory)

    if (-not (Test-PathContains -Directory $Directory)) { return }

    $wanted = $Directory.TrimEnd('\')
    $kept = @(Get-UserPathEntries | Where-Object { $_.TrimEnd('\') -ine $wanted })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    Write-Info "Removed $Directory from your user PATH."
}

function Get-InstallDirectory {
    if ($Prefix) { return $Prefix }
    if (-not $env:LOCALAPPDATA) {
        Write-Fail 'LOCALAPPDATA is not set. Pass -Prefix <dir>.'
    }
    return (Join-Path $env:LOCALAPPDATA "Programs\$BinName")
}

function Invoke-Uninstall {
    $dir = Get-InstallDirectory
    $exe = Join-Path $dir $ExeName

    if (Test-Path -LiteralPath $exe) {
        Remove-Item -LiteralPath $exe -Force
        Write-Info "Removed $exe"
    } else {
        Write-Info "No $ExeName found in $dir."
    }

    Remove-FromUserPath -Directory $dir

    if (Test-Path -LiteralPath $dir) {
        $remaining = @(Get-ChildItem -LiteralPath $dir -Force)
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $dir -Force
            Write-Info "Removed the empty directory $dir"
        }
    }

    Write-Info ''
    Write-Info "ConfAI also keeps user data in $env:USERPROFILE\.confai (presets, agent rosters)."
    Write-Info 'It was left alone. Remove it with:  Remove-Item -Recurse -Force $env:USERPROFILE\.confai'
}

function Invoke-Install {
    $target = Get-TargetTriple
    Initialize-Tls

    if ($Version) {
        $tag = $Version
        if (-not $tag.StartsWith('v')) { $tag = "v$tag" }
    } else {
        Write-Info 'Resolving the latest release...'
        $tag = Resolve-LatestTag
    }

    $releaseVersion = $tag.TrimStart('v')
    $stem = "$BinName-$releaseVersion-$target"
    $archive = "$stem.zip"
    $base = "https://github.com/$Repo/releases/download/$tag"

    $dir = Get-InstallDirectory
    $exe = Join-Path $dir $ExeName

    if ((-not $Force) -and (Test-Path -LiteralPath $exe)) {
        $installed = ''
        try {
            # `-V` is the terse "confai X.Y.Z"; `--version` prints the wordmark.
            $installed = (& $exe -V 2>$null | Select-Object -First 1)
        } catch {
            $installed = ''
        }
        if ($installed -and ($installed -match [regex]::Escape($releaseVersion))) {
            Write-Info "$BinName $releaseVersion is already installed in $dir. Use -Force to reinstall."
            Add-ToUserPath -Directory $dir
            return
        }
    }

    Write-Info "Installing $BinName $releaseVersion ($target) into $dir"

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("confai-install-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null

    try {
        $archivePath = Join-Path $tmp $archive
        $sumsPath = Join-Path $tmp 'SHA256SUMS'

        Write-Info "Downloading $archive"
        try {
            Invoke-WebRequest -Uri "$base/$archive" -OutFile $archivePath -UseBasicParsing
        } catch {
            Write-Fail "Download failed: $base/$archive`nCheck that $target is published for $tag at https://github.com/$Repo/releases`n$($_.Exception.Message)"
        }

        Write-Info 'Downloading SHA256SUMS'
        try {
            Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile $sumsPath -UseBasicParsing
        } catch {
            Write-Fail "Could not download SHA256SUMS for $tag. Refusing to install an unverified binary."
        }

        $expected = Get-ExpectedHash -SumsPath $sumsPath -FileName $archive
        if (-not $expected) {
            Write-Fail "SHA256SUMS for $tag has no entry for $archive. Refusing to install."
        }

        $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash

        if ($actual -ine $expected) {
            Write-Host ''
            Write-Host 'CHECKSUM MISMATCH -- NOTHING WAS INSTALLED' -ForegroundColor Red
            Write-Host "  file:     $archive"
            Write-Host "  expected: $expected"
            Write-Host "  actual:   $actual"
            Write-Host ''
            Write-Fail "The download does not match the checksum published with the release. Do not use it. Retry; if it happens again, open an issue at https://github.com/$Repo/issues"
        }

        Write-Info 'Checksum verified.'

        $extracted = Join-Path $tmp 'x'
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extracted -Force

        $stagedExe = Join-Path (Join-Path $extracted $stem) $ExeName
        if (-not (Test-Path -LiteralPath $stagedExe)) {
            Write-Fail "$archive did not contain $stem\$ExeName"
        }

        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        # Copy under a temporary name in the destination, then move into place,
        # so a failure never leaves a half-written confai.exe on PATH. Windows
        # will not overwrite a running executable, which is worth saying plainly.
        $staging = Join-Path $dir ($ExeName + '.new')
        Copy-Item -LiteralPath $stagedExe -Destination $staging -Force
        try {
            Move-Item -LiteralPath $staging -Destination $exe -Force
        } catch {
            Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
            Write-Fail "Could not replace $exe. Close any running $BinName and try again. $($_.Exception.Message)"
        }

        Write-Info "Installed $exe"
        Add-ToUserPath -Directory $dir

        Write-Info ''
        Write-Info "Run '$BinName' with no arguments for the interactive view, or '$BinName --help'."
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($Uninstall) {
    Invoke-Uninstall
} else {
    Invoke-Install
}
