#Requires -Version 5.1
<#
.SYNOPSIS
    Instala dotfiles copiando arquivos para os locais corretos.

.DESCRIPTION
    Este script escaneia a pasta $HOME/ e copia os arquivos para os
    destinos correspondentes, similar ao GNU Stow mas com copias reais.
    
    Convencao de pastas:
    - $HOME/ -> %USERPROFILE%
    
    Arquivos especiais:
    - windows-terminal.json -> %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal*\LocalState\settings.json
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$script:DotfilesRoot = $PSScriptRoot

# Carrega funcoes compartilhadas
. (Join-Path $PSScriptRoot "lib\Common.ps1")

# ============================================================================
# Main
# ============================================================================

function Install-Dotfiles {
    Write-Header "Dotfiles Installer"
    
    $successCount = 0
    $errorCount = 0
    $skippedCount = 0
    
    $folderMappings = Get-FolderMappings
    
    # Processa cada pasta mapeada
    foreach ($folderName in $folderMappings.Keys) {
        $sourceFolder = Join-Path $script:DotfilesRoot $folderName
        $destBase = $folderMappings[$folderName]
        
        if (-not (Test-Path $sourceFolder)) {
            Write-Status "Pasta fonte nao encontrada: $sourceFolder" -Type Warning
            continue
        }
        
        Write-Status "Processando: $folderName -> $destBase" -Type Info
        Write-Host ""
        
        # Escaneia todos os arquivos recursivamente
        $files = Get-MappedFiles -FolderPath $sourceFolder
        
        foreach ($file in $files) {
            try {
                $targetPath = Get-SystemPath -SourceFile $file.FullName -SourceFolder $sourceFolder -DestinationBase $destBase
                
                if (-not $targetPath) {
                    $skippedCount++
                    continue
                }
                
                $copied = Copy-WithDirectory -Source $file.FullName -Destination $targetPath -DryRun:$DryRun
                if ($copied) {
                    $successCount++
                }
            }
            catch {
                Write-Status "Erro ao copiar '$($file.Name)': $_" -Type Error
                $errorCount++
            }
        }
    }
    
    # Resumo
    Write-Host ""
    Write-Header "Resumo"
    Write-Status "Arquivos copiados: $successCount" -Type Success
    
    if ($skippedCount -gt 0) {
        Write-Status "Arquivos ignorados: $skippedCount" -Type Warning
    }
    
    if ($errorCount -gt 0) {
        Write-Status "Erros: $errorCount" -Type Error
    }
    
    if ($DryRun) {
        Write-Host ""
        Write-Status "Modo DRY-RUN: nenhuma alteracao foi feita" -Type Warning
    }
}

Install-Dotfiles
