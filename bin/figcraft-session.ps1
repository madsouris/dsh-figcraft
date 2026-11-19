#Requires -Version 5.1
<#
.SYNOPSIS
  On-demand FigCraft launcher for Windows.

.DESCRIPTION
  FigCraft exposes its MCP control port only when it starts with --control PORT.
  This script starts figcraft.exe that way and stops it again. Nothing starts at
  login.

  This file is also reachable as figon, figoff, figstat and figcli through the
  .cmd shims that install.ps1 copies beside it.

  Run it from a normal terminal. A shell inside an agent sandbox can pass that
  sandbox to FigCraft, which then fails to save files outside it.

.EXAMPLE
  .\figcraft-session.ps1 up C:\Designs\MyApp.figcraft
  .\figcraft-session.ps1 status
  .\figcraft-session.ps1 down
  .\figcraft-session.ps1 cli info C:\Designs\MyApp.figcraft
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Action = 'status',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Rest
)

$ErrorActionPreference = 'Stop'

$Port = 7979
$AppId = 'figcraft'
$StateDir = Join-Path $env:LOCALAPPDATA 'dsh-figcraft'
$PidFile = Join-Path $StateDir 'app.pid'
$LogOut = Join-Path $StateDir 'control.out.log'
$LogErr = Join-Path $StateDir 'control.err.log'
$ConfigFile = Join-Path $env:APPDATA 'dsh-figcraft\config.ps1'

if (Test-Path -LiteralPath $ConfigFile) {
    . $ConfigFile
}

function Get-StandardDirs {
    $dirs = New-Object System.Collections.Generic.List[string]

    if ($env:FIGCRAFT_APP) {
        $dirs.Add((Split-Path -Parent $env:FIGCRAFT_APP))
    }

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

function Find-App {
    if ($env:FIGCRAFT_APP -and (Test-Path -LiteralPath $env:FIGCRAFT_APP)) {
        return (Resolve-Path -LiteralPath $env:FIGCRAFT_APP).Path
    }

    foreach ($dir in Get-StandardDirs) {
        $candidate = Join-Path $dir 'figcraft.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $command = Get-Command 'figcraft.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    return $null
}

function Find-Cli {
    if ($env:FIGCRAFT_CLI -and (Test-Path -LiteralPath $env:FIGCRAFT_CLI)) {
        return $env:FIGCRAFT_CLI
    }

    $app = Find-App
    if ($app) {
        $candidate = Join-Path (Split-Path -Parent $app) 'figcraft-cli.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    foreach ($dir in Get-StandardDirs) {
        $candidate = Join-Path $dir 'figcraft-cli.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $command = Get-Command 'figcraft-cli.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    return $null
}

function Test-ControlPort {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(300)) { return $false }
        $client.EndConnect($result)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-FigCraftProcesses {
    return @(Get-Process -Name $AppId -ErrorAction SilentlyContinue)
}

function Open-InApp {
    param([string] $Path)

    $payload = @{
        id     = 1
        method = 'engine.execute'
        params = @{
            command = 'file.open'
            params  = @{ path = $Path }
        }
    } | ConvertTo-Json -Depth 8 -Compress

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', $Port)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 30000
        $stream.WriteTimeout = 30000

        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.NewLine = "`n"
        $reader = New-Object System.IO.StreamReader($stream)

        $writer.WriteLine($payload)
        $writer.Flush()

        $reply = $reader.ReadLine()
        if (-not $reply) { throw 'FigCraft closed the control connection.' }

        $result = $reply | ConvertFrom-Json
        if (-not $result.ok) { throw "FigCraft refused: $($result.error)" }
    } finally {
        $client.Close()
    }
}

function Wait-ControlPort {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-ControlPort) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Start-FigCraft {
    param([string] $File)

    $app = Find-App
    if (-not $app) {
        throw 'FigCraft is not installed. Install the MSI or extract the portable ZIP, then run scripts/install.ps1 -AppDir <folder>.'
    }

    $cli = Find-Cli
    if (-not $cli) {
        throw 'figcraft-cli.exe was not found next to figcraft.exe. FigCraft 0.18.1 or later installs it.'
    }

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

    if (Test-ControlPort) {
        Write-Host "FigCraft is already running with the control port $Port."
        if ($File) {
            Open-InApp $File
            Write-Host "Opened $File"
        }
        Write-Host "CLI:  $cli"
        Write-Host 'Stop with: figoff'
        return
    }

    if ((Get-FigCraftProcesses).Count -gt 0) {
        throw 'FigCraft is running without the control port. Save your work, quit it, then run figon again.'
    }

    $process = Start-Process -FilePath $app `
        -ArgumentList @('--control', "$Port") `
        -WorkingDirectory (Split-Path -Parent $app) `
        -RedirectStandardOutput $LogOut `
        -RedirectStandardError $LogErr `
        -PassThru

    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ascii

    if (-not (Wait-ControlPort)) {
        throw "FigCraft started but port $Port did not open. See $LogOut and $LogErr."
    }

    Write-Host "FigCraft started with the control port $Port."

    if ($File) {
        Open-InApp $File
        Write-Host "Opened $File"
    }

    Write-Host "CLI:  $cli"
    Write-Host 'Start DSH now, or restart it if it was running before FigCraft.'
    Write-Host 'Stop with: figoff'
}

function Stop-FigCraft {
    $processes = Get-FigCraftProcesses

    if ($processes.Count -eq 0) {
        Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
        Write-Host 'FigCraft is not running.'
        return
    }

    foreach ($process in $processes) {
        $null = $process.CloseMainWindow()
    }

    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and (Get-FigCraftProcesses).Count -gt 0) {
        Start-Sleep -Milliseconds 250
    }

    if ((Get-FigCraftProcesses).Count -gt 0) {
        throw 'FigCraft is still running. Save your work and quit it from the app.'
    }

    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
    Write-Host 'FigCraft stopped.'
}

function Show-Status {
    $app = Find-App
    $cli = Find-Cli

    if (Test-ControlPort) {
        Write-Host "FigCraft: running (control port $Port open)"
    } elseif ((Get-FigCraftProcesses).Count -gt 0) {
        Write-Host 'FigCraft: running WITHOUT the control port'
    } else {
        Write-Host 'FigCraft: stopped'
    }

    if ($app) {
        $version = (Get-Item -LiteralPath $app).VersionInfo.ProductVersion
        if ($version) {
            Write-Host "app:      $app (v$version)"
        } else {
            Write-Host "app:      $app"
        }
    } else {
        Write-Host 'app:      missing'
    }

    if ($cli) {
        $version = (& $cli --version 2>$null | Select-Object -First 1)
        if ($version) {
            Write-Host "cli:      $cli ($version)"
        } else {
            Write-Host "cli:      $cli"
        }
    } else {
        Write-Host 'cli:      missing'
    }

    if (Test-Path -LiteralPath $PidFile) {
        Write-Host "pid:      $(Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue)"
    }
}

function Invoke-FigCraftCli {
    $cli = Find-Cli
    if (-not $cli) {
        throw 'figcraft-cli.exe was not found. Install FigCraft 0.18.1 or later.'
    }

    $arguments = @($Rest)
    & $cli @arguments
    exit $LASTEXITCODE
}

function Show-Usage {
    Write-Host 'usage: figcraft-session.ps1 {up [file] | down | status | cli <args...>}'
}

switch ($Action.ToLowerInvariant()) {
    'up' {
        $file = $null
        if (@($Rest).Count -gt 0) { $file = @($Rest)[0] }
        Start-FigCraft $file
    }
    'down' {
        Stop-FigCraft
    }
    'status' {
        Show-Status
    }
    'cli' {
        Invoke-FigCraftCli
    }
    default {
        Show-Usage
        exit 2
    }
}
