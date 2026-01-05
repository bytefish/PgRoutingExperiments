# --- DEFINE CONFIGURATION ---
$DB_CONFIG = @{
    DB_USER             = "postgis"
    DB_PASS             = "postgis"
    DB_NAME             = "routing_db"
    PBF_LOCAL_FOLDER    = "C:\Users\philipp\Downloads"
    PBF_FILENAME        = "muenster-regbez-260102.osm.pbf"
    SQL_INIT_FILE       = "$PSScriptRoot\sql\init-database.sql"
    SQL_OSM2PO_FILE     = "$PSScriptRoot\sql\osm2po.sql"
    SQL_ROUTING_FILE    = "$PSScriptRoot\sql\routing.sql"
    SQL_GEOCODING_FILE  = "$PSScriptRoot\sql\geocoding.sql"
    SQL_DEBUGGING_FILE  = "$PSScriptRoot\sql\debugging.sql"
    CONTAINER_NAME      = "routing-db"
}

# Set environment variables for Docker Compose
foreach ($key in $DB_CONFIG.Keys) {
    Set-Item -Path "env:$key" -Value $DB_CONFIG[$key]
}

function Wait-ForPostGis {
    param ([int]$maxAttempts = 30)
    Write-Host "Waiting for PostGIS to be fully initialized..." -ForegroundColor Gray
    
    for ($i = 1; $i -le $maxAttempts; $i++) {
        $check = docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -tAc "SELECT postgis_full_version();" 2>$null
        if ($lastExitCode -eq 0 -and $check -like "*POSTGIS*") {
            Write-Host "PostGIS is ready!" -ForegroundColor Green
            return $true
        }
        Write-Host "PostGIS not ready yet (Attempt $i/$maxAttempts)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
    return $false
}

function Invoke-SqlStatement {
    param ([string]$sql, [string]$message = "Executing SQL Statement...")
    Write-Host $message -ForegroundColor Gray
    return docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -tAc "$sql"
}

function Invoke-SqlFile {
    param ([string]$filePath, [string]$targetName)
    if (Test-Path $filePath) {
        Write-Host "Applying $targetName..." -ForegroundColor Cyan
        docker cp $filePath "$($DB_CONFIG.CONTAINER_NAME):/$targetName"
        docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -f "/$targetName"
    } else {
        Write-Warning "File not found: $filePath"
    }
}

# --- MAIN ORCHESTRATION ---
Write-Host "--- Orchestrating Infrastructure ---" -ForegroundColor Cyan

docker-compose --profile dev up -d

# Wait another 5 seconds for PostGIS to fully boot up
Start-Sleep -Seconds 5

if (-not (Wait-ForPostGis)) {
    Write-Error "PostGIS failed to initialize. Exiting."
    exit 1
}

# DATABASE PREPARATION (Extensions & Schemas)
Invoke-SqlFile -filePath $DB_CONFIG.SQL_INIT_FILE -targetName "init.sql"

# IDEMPOTENT ROUTING IMPORT (osm2po)
$routingExists = Invoke-SqlStatement -sql "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'routing' AND table_name = 'osm2po_data');"

if ($routingExists -ne "t") {
    Write-Host "--- Importing OSM Routing Data (osm2po) ---" -ForegroundColor Cyan
    $env:OSM_FILE = $env:PBF_FILENAME
    docker-compose --profile import run --rm osm2po
} else {
    Write-Host "Routing data already exists. Skipping osm2po." -ForegroundColor Yellow
}

# IDEMPOTENT GEOCODER IMPORT (osm2pgsql)
$geocoderExists = Invoke-SqlStatement -sql "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'planet_osm_line');"

if ($geocoderExists -ne "t") {
    
    Write-Host "--- Importing OSM Geocoding Data (osm2pgsql) ---" -ForegroundColor Cyan

    docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -c "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pgrouting;"
    
    # Check if osm2pgsql is installed, install if missing
    $hasOsm = docker exec $DB_CONFIG.CONTAINER_NAME which osm2pgsql
    
    if (!$hasOsm) {
        Write-Host "osm2pgsql not found. Installing..." -ForegroundColor Yellow
        
        docker exec -u root $DB_CONFIG.CONTAINER_NAME apt-get update
        docker exec -u root $DB_CONFIG.CONTAINER_NAME apt-get install -y osm2pgsql
    }
    
    docker exec -it $DB_CONFIG.CONTAINER_NAME osm2pgsql --create --database $env:DB_NAME --username $env:DB_USER --hstore-all --proj 4326 --slim "/osm_import/$($env:PBF_FILENAME)"
}

# APPLY LOGIC (Functions, Views, Indexes)
Invoke-SqlFile -filePath $DB_CONFIG.SQL_OSM2PO_FILE -targetName "osm2po.sql"
Invoke-SqlFile -filePath $DB_CONFIG.SQL_ROUTING_FILE -targetName "routing.sql"
Invoke-SqlFile -filePath $DB_CONFIG.SQL_GEOCODING_FILE -targetName "geocoding.sql"
Invoke-SqlFile -filePath $DB_CONFIG.SQL_DEBUGGING_FILE -targetName "network.sql"

Write-Host "--- DEPLOYMENT FINISHED ---" -ForegroundColor Green