#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Instala o desinstala PaqAgent como servicio de Windows.

.DESCRIPTION
    Script de instalacion para el agente local PAQSuite IA Tango.
    Compila (opcional), copia archivos y registra el servicio Windows.

.PARAMETER Action
    install | uninstall | start | stop | restart

.PARAMETER InstallPath
    Ruta de instalacion. Por defecto: C:\PaqSuite\PaqAgent

.PARAMETER Build
    Si se especifica, compila el proyecto antes de instalar.

.EXAMPLE
    .\install-service.ps1 -Action install -Build

.EXAMPLE
    .\install-service.ps1 -Action uninstall
#>

param(
    [ValidateSet("install", "uninstall", "start", "stop", "restart")]
    [string]$Action = "install",

    [string]$InstallPath = "C:\PaqSuite\PaqAgent",

    [switch]$Build
)

$ServiceName = "PaqAgent"
$ServiceDisplayName = "PAQSuite IA Tango - Agente Local"
$ServiceDescription = "Agente local para consultas SQL Server Tango via Agent Gateway"
$ProjectPath = Join-Path $PSScriptRoot ".." "PaqAgent.csproj"

function Test-DotNet {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        $defaultPath = "C:\Program Files\dotnet\dotnet.exe"
        if (Test-Path $defaultPath) { return $defaultPath }
        throw "No se encontro .NET SDK. Instale .NET 8 desde https://dotnet.microsoft.com/download"
    }
    return $dotnet.Source
}

function Build-Project {
    $dotnet = Test-DotNet
    Write-Host "Compilando proyecto..." -ForegroundColor Cyan
    & $dotnet publish $ProjectPath -c Release -o $InstallPath --self-contained false
    if ($LASTEXITCODE -ne 0) { throw "Error al compilar el proyecto" }
    Write-Host "Compilacion exitosa en $InstallPath" -ForegroundColor Green
}

function Install-Service {
    if ($Build) { Build-Project }

    if (-not (Test-Path (Join-Path $InstallPath "PaqAgent.exe"))) {
        throw "No se encontro PaqAgent.exe en $InstallPath. Use -Build o copie los archivos manualmente."
    }

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "El servicio ya existe. Deteniendo y eliminando..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }

    $exePath = Join-Path $InstallPath "PaqAgent.exe"
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallPath "logs") | Out-Null

    sc.exe create $ServiceName binPath= "`"$exePath`"" DisplayName= "$ServiceDisplayName" start= auto | Out-Null
    sc.exe description $ServiceName "$ServiceDescription" | Out-Null

    Write-Host "Servicio $ServiceName instalado en $InstallPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANTE: Configure appsettings.json antes de iniciar:" -ForegroundColor Yellow
    Write-Host "  - Agent.AgentId y Agent.AgentToken" -ForegroundColor Yellow
    Write-Host "  - Agent.GatewayUrl" -ForegroundColor Yellow
    Write-Host "  - SqlConnection (Server, Database, User, Password)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Para iniciar: .\install-service.ps1 -Action start" -ForegroundColor Cyan
}

function Uninstall-Service {
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
        Write-Host "Servicio $ServiceName desinstalado" -ForegroundColor Green
    } else {
        Write-Host "El servicio $ServiceName no esta instalado" -ForegroundColor Yellow
    }
}

switch ($Action) {
    "install"   { Install-Service }
    "uninstall" { Uninstall-Service }
    "start"     { Start-Service -Name $ServiceName; Write-Host "Servicio iniciado" -ForegroundColor Green }
    "stop"      { Stop-Service -Name $ServiceName -Force; Write-Host "Servicio detenido" -ForegroundColor Green }
    "restart"   { Restart-Service -Name $ServiceName -Force; Write-Host "Servicio reiniciado" -ForegroundColor Green }
}
