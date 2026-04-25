#Requires -Version 5.1
<#
.SYNOPSIS
    Busca dotfiles do sistema para o repositorio.

.DESCRIPTION
    Este script escaneia os arquivos existentes no repositorio e busca
    as versoes atuais do sistema, copiando para o repositorio.
    
    Isso permite atualizar o repositorio com mudancas feitas diretamente
    nos arquivos de configuracao do sistema.
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

function Get-Dotfiles {
    Write-Header "Dotfiles Fetcher"
    
    $successCount = 0
    $errorCount = 0
    $skippedCount = 0
    
    $folderMappings = Get-FolderMappings
    
    # Processa cada pasta mapeada
    foreach ($folderName in $folderMappings.Keys) {
        $repoFolder = Join-Path $script:DotfilesRoot $folderName
        $systemBase = $folderMappings[$folderName]
        
        if (-not (Test-Path $repoFolder)) {
            Write-Status "Pasta do repositorio nao encontrada: $repoFolder" -Type Warning
            continue
        }
        
        Write-Status "Buscando: $systemBase -> $folderName" -Type Info
        Write-Host ""
        
        # Escaneia arquivos existentes no repositorio
        $repoFiles = Get-MappedFiles -FolderPath $repoFolder
        
        foreach ($repoFile in $repoFiles) {
            try {
                # Encontra o arquivo correspondente no sistema
                $systemPath = Get-SystemPath -SourceFile $repoFile.FullName -SourceFolder $repoFolder -DestinationBase $systemBase
                
                if (-not $systemPath) {
                    $skippedCount++
                    continue
                }
                
                if (-not (Test-Path $systemPath)) {
                    Write-Status "Arquivo nao existe no sistema: $systemPath" -Type Warning
                    $skippedCount++
                    continue
                }
                
                # Copia do sistema para o repositorio
                $copied = Copy-WithDirectory -Source $systemPath -Destination $repoFile.FullName -DryRun:$DryRun
                if ($copied) {
                    $successCount++
                }
            }
            catch {
                Write-Status "Erro ao buscar '$($repoFile.Name)': $_" -Type Error
                $errorCount++
            }
        }
    }
    
    # Resumo
    Write-Host ""
    Write-Header "Resumo"
    Write-Status "Arquivos atualizados: $successCount" -Type Success
    
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

Get-Dotfiles
