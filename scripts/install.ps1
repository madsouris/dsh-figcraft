#Requires -Version 5.1
<#
.SYNOPSIS
  Install the FigCraft launcher for DeepSeek Harness on Windows.

.DESCRIPTION
  Copies figcraft-session.ps1 and the figon/figoff/figstat/figcli shims into a
  folder on PATH, then adds the FigCraft install folder to PATH so the DSH MCP
  row can start figcraft-cli.exe directly.

  The MSI and the portable ZIP both contain figcraft.exe and figcraft-cli.exe.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1

.EXAMPLE
  .\scripts\install.ps1 -AppDir "C:\Users\me\Apps\figcraft-0.18.1-windows-x64-portable"
#>
[CmdletBinding()]
param(
    [string] $Prefix = "$env:USERPROFILE\.local\bin",

    [string] $AppDir = "",

    [switch] $NoPath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Get-StandardDirs {
    $dirs = New-Object System.Collections.Generic.List[string]

    foreach ($key in @(
            'HKCU:\Software\FigCraft',
            'HKLM:\Software\FigCraft',
            'HKLM:\Software\WOW6432Node\FigCraft'
        )) {
        try {
            $value = (Get-ItemProperty -Path $key -Name InstallDir -ErrorAction Stop).InstallDir
            if ($value) { $dirs.Add($value) }
        } catch {
        }
    }

    if ($env:ProgramFiles) {
        $dirs.Add((Join-Path $env:ProgramFiles 'ArtCraft\FigCraft'))
    }
    if (${env:ProgramFiles(x86)}) {
        $dirs.Add((Join-Path ${env:ProgramFiles(x86)} 'ArtCraft\FigCraft'))
    }
    if ($env:LOCALAPPDATA) {
        $dirs.Add((Join-Path $env:LOCALAPPDATA 'Programs\ArtCraft\FigCraft'))
    }

    return $dirs | Where-Object { $_ } | Select-Object -Unique
}

function Find-AppDir {
    if ($AppDir) {
        $candidate = Join-Path $AppDir 'figcraft.exe'
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "No figcraft.exe in $AppDir"
        }
        return (Resolve-Path -LiteralPath $AppDir).Path
    }

    foreach ($dir in Get-StandardDirs) {
        if (Test-Path -LiteralPath (Join-Path $dir 'figcraft.exe')) {
            return $dir
        }
    }

    $command = Get-Command 'figcraft.exe' -ErrorAction SilentlyContinue
    if ($command) { return (Split-Path -Parent $command.Source) }

    return $null
}

function Add-UserPath {
    param([string] $Dir)

    if (-not $Dir) { return }

    $resolved = (Resolve-Path -LiteralPath $Dir).Path
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) {
        $parts = @($userPath -split ';' | Where-Object { $_ })
    }

    if ($parts -notcontains $resolved) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $resolved) -join ';'), 'User')
        Write-Host "Added to the user PATH: $resolved"
    }

    if (-not (($env:Path -split ';') -contains $resolved)) {
        $env:Path = "$resolved;$env:Path"
    }
}

New-Item -ItemType Directory -Force -Path $Prefix | Out-Null

foreach ($file in @('figcraft-session.ps1', 'figon.cmd', 'figoff.cmd', 'figstat.cmd', 'figcli.cmd')) {
    Copy-Item -LiteralPath (Join-Path $Root "bin\$file") -Destination (Join-Path $Prefix $file) -Force
}

Write-Host "Installed launchers in $Prefix"

$foundAppDir = Find-AppDir

if (-not $foundAppDir) {
    Write-Host ''
    Write-Host 'FigCraft was not found.' -ForegroundColor Yellow
    Write-Host 'Install FigCraft 0.18.1 or later from:'
    Write-Host '  https://github.com/storytold/figcraft/releases/latest'
    Write-Host 'For the portable ZIP, run this script again with:'
    Write-Host '  .\scripts\install.ps1 -AppDir "C:\path\to\figcraft-0.18.1-windows-x64-portable"'
    exit 1
}

$cli = Join-Path $foundAppDir 'figcraft-cli.exe'
if (-not (Test-Path -LiteralPath $cli)) {
    Write-Warning "figcraft-cli.exe is missing from $foundAppDir. FigCraft 0.18.1 or later includes it."
}

if ($NoPath) {
    Write-Host ''
    Write-Host 'PATH was left unchanged. Add both folders to PATH yourself:'
    Write-Host "  $Prefix"
    Write-Host "  $foundAppDir"
} else {
    Add-UserPath $Prefix
    Add-UserPath $foundAppDir
}

Write-Host ''
Write-Host "FigCraft: $foundAppDir"
Write-Host "CLI:      $cli"
Write-Host ''
Write-Host 'Open a new terminal, then start FigCraft before DSH:'
Write-Host '  figon'
Write-Host ''
Write-Host 'If DSH was already running, restart it so it picks up the new PATH.'
