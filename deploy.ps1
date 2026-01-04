# --- DEFINE CONFIGURATION ---
$DB_CONFIG = @{
    DB_USER           = "postgis"
    DB_PASS           = "postgis"
    DB_NAME           = "routing_db"
    PBF_LOCAL_FOLDER  = "C:\Users\philipp\Downloads"
    PBF_FILENAME      = "muenster-regbez-260102.osm.pbf"
    SQL_LOGIC_FILE    = "$PSScriptRoot\sql\routing_logic.sql"
    CONTAINER_NAME    = "routing-db"
}

# Safely set environment variables so Docker Compose can read them
foreach ($key in $DB_CONFIG.Keys) {
    Set-Item -Path "env:$key" -Value $DB_CONFIG[$key]
}

Write-Host "--- Orchestrating Infrastructure ---" -ForegroundColor Cyan
docker-compose --profile dev up -d

# --- WAIT FOR DB ---
Write-Host "Waiting for PostGIS to be fully initialized..." -ForegroundColor Gray

$maxAttempts = 30
$attempt = 0
$isPostGisReady = $false

while (!$isPostGisReady -and $attempt -lt $maxAttempts) {
    
    $checkPostGis = docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -tAc "SELECT postgis_full_version();" 2>$null
    
    if ($lastExitCode -eq 0 -and $checkPostGis -like "*POSTGIS*") {
        $isPostGisReady = $true
        Write-Host "PostGIS is ready!" -ForegroundColor Green
    } else {
        $attempt++
        Write-Host "PostGIS not ready yet (Attempt $attempt/$maxAttempts)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}

if (!$isPostGisReady) {
    Write-Error "PostGIS failed to initialize within the expected time."
    exit 1
}

# DATABASE PREPARATION ---
Write-Host "--- Preparing Extensions ---" -ForegroundColor Cyan
# Ensure the database exists
docker exec $DB_CONFIG.CONTAINER_NAME psql -U $env:DB_USER -d  $env:DB_NAME -c "SELECT 1 FROM pg_database WHERE datname = '$($env:DB_NAME)'" | Select-String "1" > $null
if ($lastExitCode -ne 0) {
    docker exec $DB_CONFIG.CONTAINER_NAME psql -U $env:DB_USER -d $env:DB_NAME -c "CREATE DATABASE $($env:DB_NAME);"
}

# Create extensions inside the target database
docker exec $DB_CONFIG.CONTAINER_NAME psql -U $env:DB_USER -d $env:DB_NAME -c "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pgrouting; CREATE EXTENSION IF NOT EXISTS postgis;"

# --- IDEMPOTENT IMPORT ---
Write-Host "Checking if table exists..." -ForegroundColor Gray
$tableExists = docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -tAc `
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'road_network');"

if ($tableExists -ne "t") {
    Write-Host "--- Importing OSM Data ---" -ForegroundColor Cyan
    # Ensure extensions exist
    docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -c "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pgrouting;"
    
    # Check if osm2pgsql is installed, install if missing
    $hasOsm = docker exec $DB_CONFIG.CONTAINER_NAME which osm2pgsql
    if (!$hasOsm) {
        Write-Host "osm2pgsql not found. Installing..." -ForegroundColor Yellow
        docker exec -u root $DB_CONFIG.CONTAINER_NAME apt-get update
        docker exec -u root $DB_CONFIG.CONTAINER_NAME apt-get install -y osm2pgsql
    }

    docker exec -it $DB_CONFIG.CONTAINER_NAME osm2pgsql `
        --create --database $env:DB_NAME --username $env:DB_USER `
        --hstore --proj 4326 --slim "/osm_import/$($env:PBF_FILENAME)"
} else {
    Write-Host "Table 'road_network' already exists. Skipping PBF import." -ForegroundColor Yellow
}

# --- APPLY SQL LOGIC ---
Write-Host "--- Applying Routing Logic & Functions ---" -ForegroundColor Cyan
if (Test-Path $DB_CONFIG.SQL_LOGIC_FILE) {
    docker cp $DB_CONFIG.SQL_LOGIC_FILE "$($DB_CONFIG.CONTAINER_NAME):/routing_logic.sql"
    docker exec $DB_CONFIG.CONTAINER_NAME psql -d $env:DB_NAME -U $env:DB_USER -f /routing_logic.sql
} else {
    Write-Warning "SQL Logic file not found!"
}

Write-Host "--- DEPLOYMENT FINISHED ---" -ForegroundColor Green
Write-Host "Database: $($env:DB_NAME) | User: $($env:DB_USER)"