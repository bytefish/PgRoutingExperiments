#!/bin/bash
set -e # Exit on any error

echo "Starting osm2po Tiling and SQL Generation..."
java -Xmx4g -cp "/opt/osm2po/*" de.cm.osm2po.Main \
    config=/opt/osm2po/osm2po.config \
    prefix=sw_all \
    workDir=/opt/osm2po \
    cmd=tjsgp \
    /data/${PBF_FILENAME}

# The path osm2po created (based on your last log)
SQL_FILE="/opt/osm2po/sw_all_2po_4pgr.sql"

if [ -f "$SQL_FILE" ]; then
    echo "--- SQL file generated. Importing into PostgreSQL ---"
    export PGPASSWORD=$DB_PASS
    psql -h routing-db -U $DB_USER -d $DB_NAME -q -f "$SQL_FILE"
    
    echo "--- Moving Table and Creating Indexes ---"
    psql -h routing-db -U $DB_USER -d $DB_NAME -c "
        -- Create Routing Schema, if not exists
        CREATE SCHEMA IF NOT EXISTS routing;

        -- DROP Table for a clean re-import
        DROP TABLE IF EXISTS routing.osm2po_data;

        -- Move and Rename the Table
        ALTER TABLE public.sw_all_2po_4pgr SET SCHEMA routing;
        ALTER TABLE routing.sw_all_2po_4pgr RENAME TO osm2po_data;

        -- Build Spatial Index
        CREATE INDEX idx_osm2po_data_geom ON routing.osm2po_data USING GIST (geom_way);
        
        -- Routing Indizes
        CREATE INDEX idx_osm2po_data_source ON routing.osm2po_data (source);
        CREATE INDEX idx_osm2po_data_target ON routing.osm2po_data (target);
        
        ANALYZE routing.osm2po_data;
    "
    
    echo "--- Cleaning up ---"
    rm "$SQL_FILE"
    echo "SUCCESS: Table is now at routing.osm2po_data and optimized!"
else
    echo "ERROR: SQL file not found at $SQL_FILE"
    exit 1
fi