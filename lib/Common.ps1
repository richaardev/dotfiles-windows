# ============================================================================
# Common.ps1 - Funcoes compartilhadas para dotfiles
# ============================================================================

# ============================================================================
# UI Functions
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
# Path Mappings
# ============================================================================

# Mapeia nome da pasta fonte -> caminho destino no sistema
function Get-FolderMappings {
    return @{
        '$HOME' = $env:USERPROFILE
    }
}

# Arquivos especiais com destinos customizados
# Retorna hashtable: nome_arquivo -> { ToSystem = scriptblock, ToRepo = scriptblock }
function Get-SpecialFiles {
    return @{
        'windows-terminal.json' = @{
            # Sistema: onde o arquivo fica instalado
            ToSystem = {
                $wtPaths = @(
                    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState"
                    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_*\LocalState"
                )
                
                foreach ($pattern in $wtPaths) {
                    $resolved = Resolve-Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($resolved) {
                        return Join-Path $resolved.Path "settings.json"
                    }
                }
                return $null
            }
            # Repo: onde guardar no repositorio (relativo a pasta mapeada)
            ToRepo = {
                param($RepoFolder)
                return Join-Path $RepoFolder "windows-terminal.json"
            }
        }
    }
}

# ============================================================================
# Path Resolution
# ============================================================================

function Get-SystemPath {
    <#
    .SYNOPSIS
        Resolve caminho do arquivo no sistema (destino do install)
    #>
    param(
        [string]$SourceFile,
        [string]$SourceFolder,
        [string]$DestinationBase
    )
    
    $fileName = Split-Path $SourceFile -Leaf
    $specialFiles = Get-SpecialFiles
    
    # Verifica se e um arquivo especial
    if ($specialFiles.ContainsKey($fileName)) {
        $specialPath = & $specialFiles[$fileName].ToSystem
        if ($specialPath) {
            return $specialPath
        }
        Write-Status "Destino especial nao encontrado para: $fileName" -Type Warning
        return $null
    }
    
    # Calcula caminho relativo e mapeia pro destino
    $relativePath = $SourceFile.Substring($SourceFolder.Length).TrimStart('\', '/')
    return Join-Path $DestinationBase $relativePath
}

function Get-RepoPath {
    <#
    .SYNOPSIS
        Resolve caminho do arquivo no repositorio (destino do get)
    #>
    param(
        [string]$SystemFile,
        [string]$RepoFolder,
        [string]$SystemBase
    )
    
    $fileName = Split-Path $SystemFile -Leaf
    $specialFiles = Get-SpecialFiles
    
    # Verifica se e um arquivo especial (por nome do arquivo no sistema)
    # Para settings.json do Windows Terminal
    if ($SystemFile -like "*WindowsTerminal*\LocalState\settings.json") {
        return & $specialFiles['windows-terminal.json'].ToRepo $RepoFolder
    }
    
    # Caminho normal: mantém estrutura relativa
    $relativePath = $SystemFile.Substring($SystemBase.Length).TrimStart('\', '/')
    return Join-Path $RepoFolder $relativePath
}

# ============================================================================
# File Operations
# ============================================================================

function Copy-WithDirectory {
    <#
    .SYNOPSIS
        Copia arquivo criando diretorios pai se necessario
    #>
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$DryRun
    )
    
    # Cria diretorio pai se nao existir
    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) {
        if ($DryRun) {
            Write-Status "[DRY-RUN] Criaria diretorio: $destDir" -Type Info
        }
        else {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Write-Status "Diretorio criado: $destDir" -Type Info
        }
    }
    
    if ($DryRun) {
        Write-Status "[DRY-RUN] Copiaria: $Source -> $Destination" -Type Info
        return $true
    }
    
    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Status "Copiado: $Source -> $Destination" -Type Success
    return $true
}

function Get-MappedFiles {
    <#
    .SYNOPSIS
        Retorna lista de arquivos de uma pasta mapeada
    #>
    param(
        [string]$FolderPath
    )
    
    if (-not (Test-Path $FolderPath)) {
        return @()
    }
    
    return Get-ChildItem -Path $FolderPath -File -Recurse
}
