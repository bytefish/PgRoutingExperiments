#!/bin/bash

# --- DEFINE CONFIGURATION ---
# Using an associative array for the config
declare -A DB_CONFIG
DB_CONFIG[DB_USER]="postgis"
DB_CONFIG[DB_PASS]="postgis"
DB_CONFIG[DB_NAME]="routing_db"
DB_CONFIG[PBF_LOCAL_FOLDER]="$HOME/Downloads"
DB_CONFIG[PBF_FILENAME]="muenster-regbez-260102.osm.pbf"
DB_CONFIG[CONTAINER_NAME]="routing-db"

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_CONFIG[SQL_INIT_FILE]="$SCRIPT_DIR/sql/init-database.sql"
DB_CONFIG[SQL_OSM2PO_FILE]="$SCRIPT_DIR/sql/osm2po.sql"
DB_CONFIG[SQL_ROUTING_FILE]="$SCRIPT_DIR/sql/routing.sql"
DB_CONFIG[SQL_GEOCODING_FILE]="$SCRIPT_DIR/sql/geocoding.sql"
DB_CONFIG[SQL_DEBUGGING_FILE]="$SCRIPT_DIR/sql/debugging.sql"
DB_CONFIG[SQL_TRSP_FILE]="$SCRIPT_DIR/sql/trsp.sql"

# Export variables for Docker Compose
for key in "${!DB_CONFIG[@]}"; do
    export "$key"="${DB_CONFIG[$key]}"
done

# --- FUNCTIONS ---

wait_for_postgis() {
    local max_attempts=30
    echo "Waiting for PostGIS to be fully initialized..."
    
    for ((i=1; i<=max_attempts; i++)); do
        # Check if PostGIS is responsive
        check=$(docker exec "${DB_CONFIG[CONTAINER_NAME]}" psql -d "${DB_CONFIG[DB_NAME]}" -U "${DB_CONFIG[DB_USER]}" -tAc "SELECT postgis_full_version();" 2>/dev/null)
        
        if [ $? -eq 0 ] && [[ "$check" == *"POSTGIS"* ]]; then
            echo -e "\e[32mPostGIS is ready!\e[0m"
            return 0
        fi
        
        echo "PostGIS not ready yet (Attempt $i/$max_attempts)..."
        sleep 3
    done
    return 1
}

invoke_sql_statement() {
    local sql="$1"
    local message="${2:-Executing SQL Statement...}"
    echo "$message"
    docker exec "${DB_CONFIG[CONTAINER_NAME]}" psql -d "${DB_CONFIG[DB_NAME]}" -U "${DB_CONFIG[DB_USER]}" -tAc "$sql"
}

invoke_sql_file() {
    local file_path="$1"
    local target_name="$2"
    
    if [ -f "$file_path" ]; then
        echo -e "\e[36mApplying $target_name...\e[0m"
        docker cp "$file_path" "${DB_CONFIG[CONTAINER_NAME]}:/$target_name"
        docker exec "${DB_CONFIG[CONTAINER_NAME]}" psql -d "${DB_CONFIG[DB_NAME]}" -U "${DB_CONFIG[DB_USER]}" -f "/$target_name"
    else
        echo -e "\e[33mWarning: File not found: $file_path\e[0m"
    fi
}

# --- MAIN ORCHESTRATION ---
echo -e "\e[36m--- Orchestrating Infrastructure ---\e[0m"

docker-compose --profile dev up -d

# Wait another 5 seconds for PostGIS to fully boot up
sleep 5

if ! wait_for_postgis; then
    echo "PostGIS failed to initialize. Exiting."
    exit 1
fi

# DATABASE PREPARATION (Extensions & Schemas)
invoke_sql_file "${DB_CONFIG[SQL_INIT_FILE]}" "init.sql"

# IDEMPOTENT ROUTING IMPORT (osm2po)
routing_exists=$(invoke_sql_statement "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'routing' AND table_name = 'osm2po_data');")

if [ "$routing_exists" != "t" ]; then
    echo -e "\e[36m--- Importing OSM Routing Data (osm2po) ---\e[0m"
    export OSM_FILE="${DB_CONFIG[PBF_FILENAME]}"
    docker-compose --profile import run --rm osm2po
else
    echo -e "\e[33mRouting data already exists. Skipping osm2po.\e[0m"
fi

# IDEMPOTENT GEOCODER IMPORT (osm2pgsql)
geocoder_exists=$(invoke_sql_statement "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'planet_osm_line');")

if [ "$geocoder_exists" != "t" ]; then
    echo -e "\e[36m--- Importing OSM Geocoding Data (osm2pgsql) ---\e[0m"

    docker exec "${DB_CONFIG[CONTAINER_NAME]}" psql -d "${DB_CONFIG[DB_NAME]}" -U "${DB_CONFIG[DB_USER]}" -c "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pgrouting;"
    
    # Check if osm2pgsql is installed
    if ! docker exec "${DB_CONFIG[CONTAINER_NAME]}" which osm2pgsql > /dev/null 2>&1; then
        echo -e "\e[33mosm2pgsql not found. Installing...\e[0m"
        docker exec -u root "${DB_CONFIG[CONTAINER_NAME]}" apt-get update
        docker exec -u root "${DB_CONFIG[CONTAINER_NAME]}" apt-get install -y osm2pgsql
    fi
    
    docker exec -it "${DB_CONFIG[CONTAINER_NAME]}" osm2pgsql --create --database "${DB_CONFIG[DB_NAME]}" --username "${DB_CONFIG[DB_USER]}" --hstore-all --proj 4326 --slim "/osm_import/${DB_CONFIG[PBF_FILENAME]}"
fi

# APPLY LOGIC (Functions, Views, Indexes)
invoke_sql_file "${DB_CONFIG[SQL_OSM2PO_FILE]}" "osm2po.sql"
invoke_sql_file "${DB_CONFIG[SQL_ROUTING_FILE]}" "routing.sql"
invoke_sql_file "${DB_CONFIG[SQL_GEOCODING_FILE]}" "geocoding.sql"
invoke_sql_file "${DB_CONFIG[SQL_DEBUGGING_FILE]}" "network.sql"
invoke_sql_file "${DB_CONFIG[SQL_TRSP_FILE]}" "trsp.sql"

echo -e "\e[32m--- DEPLOYMENT FINISHED ---\e[0m"