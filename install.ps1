#Requires -Version 5.1
<#
.SYNOPSIS
    Instala dotfiles criando symlinks para os locais corretos.

.DESCRIPTION
    Este script le o arquivo dotfiles.json e cria symlinks para cada
    mapeamento definido. Se o destino ja existir, sera sobrescrito.
#>

param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$script:DotfilesRoot = $PSScriptRoot

# ============================================================================
# Funcoes de UI
# ============================================================================

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Type = "Info"
    )
    
    $colors = @{
        Info    = "Cyan"
        Success = "Green"
        Warning = "Yellow"
        Error   = "Red"
    }
    
    $prefixes = @{
        Info    = "[*]"
        Success = "[+]"
        Warning = "[!]"
        Error   = "[x]"
    }
    
    Write-Host "$($prefixes[$Type]) " -ForegroundColor $colors[$Type] -NoNewline
    Write-Host $Message
}

function Write-Header {
    param([string]$Title)
    
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor Magenta
    Write-Host $line -ForegroundColor Magenta
    Write-Host ""
}

# ============================================================================
# Verificacao de Privilegios e Auto-Elevacao
# ============================================================================

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevate {
    Write-Status "Elevando privilegios para administrador..." -Type Warning
    
    $scriptPath = $MyInvocation.PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = $PSCommandPath
    }
    
    $arguments = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$scriptPath`""
    )
    
    if ($Force) { $arguments += "-Force" }
    if ($DryRun) { $arguments += "-DryRun" }
    
    try {
        Start-Process -FilePath "pwsh.exe" -ArgumentList $arguments -Verb RunAs -Wait
    }
    catch {
        # Fallback para Windows PowerShell se pwsh nao estiver disponivel
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -Wait
    }
    
    exit
}

# ============================================================================
# Funcoes de Symlink
# ============================================================================

function Expand-TargetPath {
    param([string]$Path)
    
    # Expande variaveis de ambiente no formato %VAR%
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    
    # Normaliza separadores de caminho
    $expanded = $expanded -replace "/", "\"
    
    return $expanded
}

function Remove-ExistingItem {
    param([string]$Path)
    
    if (Test-Path $Path) {
        $item = Get-Item $Path -Force
        
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # E um symlink, remove apenas o link
            $item.Delete()
            Write-Status "Symlink existente removido: $Path" -Type Warning
        }
        elseif ($Force) {
            # E um arquivo/pasta real, remove se -Force
            Remove-Item $Path -Recurse -Force
            Write-Status "Arquivo existente removido (--force): $Path" -Type Warning
        }
        else {
            throw "Arquivo existente nao e um symlink. Use -Force para sobrescrever: $Path"
        }
    }
}

function New-Symlink {
    param(
        [string]$Source,
        [string]$Target,
        [ValidateSet("file", "directory")]
        [string]$Type = "file"
    )
    
    $sourcePath = Join-Path $script:DotfilesRoot $Source
    $targetPath = Expand-TargetPath $Target
    
    # Valida se o source existe
    if (-not (Test-Path $sourcePath)) {
        throw "Arquivo fonte nao encontrado: $sourcePath"
    }
    
    # Cria diretorio pai do target se nao existir
    $targetDir = Split-Path $targetPath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Status "Diretorio criado: $targetDir" -Type Info
    }
    
    # Remove item existente
    Remove-ExistingItem -Path $targetPath
    
    if ($DryRun) {
        Write-Status "[DRY-RUN] Criaria symlink: $targetPath -> $sourcePath" -Type Info
        return
    }
    
    # Cria o symlink
    if ($Type -eq "directory") {
        New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath | Out-Null
    }
    else {
        New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath | Out-Null
    }
    
    Write-Status "Symlink criado: $targetPath -> $sourcePath" -Type Success
}

# ============================================================================
# Main
# ============================================================================

function Main {
    Write-Header "Dotfiles Installer"
    
    # Verifica privilegios de admin
    if (-not (Test-Administrator)) {
        Invoke-Elevate
        return
    }
    
    Write-Status "Executando como administrador" -Type Success
    
    # Carrega configuracao
    $configPath = Join-Path $script:DotfilesRoot "dotfiles.json"
    
    if (-not (Test-Path $configPath)) {
        Write-Status "Arquivo de configuracao nao encontrado: $configPath" -Type Error
        exit 1
    }
    
    Write-Status "Carregando configuracao: $configPath" -Type Info
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    
    if (-not $config.links -or $config.links.Count -eq 0) {
        Write-Status "Nenhum link definido no arquivo de configuracao" -Type Warning
        exit 0
    }
    
    Write-Status "Encontrados $($config.links.Count) link(s) para processar" -Type Info
    Write-Host ""
    
    # Processa cada link
    $successCount = 0
    $errorCount = 0
    
    foreach ($link in $config.links) {
        try {
            $type = if ($link.type) { $link.type } else { "file" }
            New-Symlink -Source $link.source -Target $link.target -Type $type
            $successCount++
        }
        catch {
            Write-Status "Erro ao criar symlink para '$($link.target)': $_" -Type Error
            $errorCount++
        }
    }
    
    # Resumo
    Write-Host ""
    Write-Header "Resumo"
    Write-Status "Links criados com sucesso: $successCount" -Type Success
    
    if ($errorCount -gt 0) {
        Write-Status "Links com erro: $errorCount" -Type Error
    }
    
    if ($DryRun) {
        Write-Host ""
        Write-Status "Modo DRY-RUN: nenhuma alteracao foi feita" -Type Warning
    }
    
    Write-Host ""
    Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Main
