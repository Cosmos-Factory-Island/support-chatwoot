# Exporta PostgreSQL + storage de Chatwoot local para migrar a producción (Coolify).
# Uso: .\scripts\export-local.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$BackupDir = Join-Path $Root "backups"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$PostgresContainer = "support-chatwoot-postgres-1"
$DbName = if ($env:CHATWOOT_DB) { $env:CHATWOOT_DB } else { "chatwoot_production" }
$DbUser = if ($env:POSTGRES_USERNAME) { $env:POSTGRES_USERNAME } else { "postgres" }

$SqlFile = Join-Path $BackupDir "chatwoot-$Timestamp.sql"
$StorageFile = Join-Path $BackupDir "storage_data-$Timestamp.tar.gz"

Write-Host "==> Comprobando contenedor $PostgresContainer..."
$running = docker inspect -f "{{.State.Running}}" $PostgresContainer 2>$null
if ($running -ne "true") {
  Write-Host "    Arrancando postgres..."
  docker start $PostgresContainer | Out-Null
  Start-Sleep -Seconds 3
}

Write-Host "==> Volcando base de datos '$DbName' -> $SqlFile"
docker exec $PostgresContainer pg_dump -U $DbUser -d $DbName --clean --if-exists --no-owner --no-acl `
  | Set-Content -Path $SqlFile -Encoding utf8

if (-not (Test-Path $SqlFile) -or (Get-Item $SqlFile).Length -lt 1024) {
  throw "El dump SQL parece vacío. ¿La BD correcta es '$DbName'? Prueba: `$env:CHATWOOT_DB='chatwoot'"
}

Write-Host "==> Empaquetando volumen storage_data -> $StorageFile"
docker run --rm `
  -v support-chatwoot_storage_data:/storage:ro `
  -v "${BackupDir}:/backup" `
  alpine tar czf "/backup/storage_data-$Timestamp.tar.gz" -C /storage .

Write-Host ""
Write-Host "Exportación completada:"
Write-Host "  SQL:     $SqlFile"
Write-Host "  Storage: $StorageFile"
Write-Host ""
Write-Host "Siguiente paso: sube ambos archivos al VPS y ejecuta scripts/import-production.sh"
