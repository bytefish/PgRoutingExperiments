#!/bin/bash
set -e

echo "--- Geocoding Import (osm2pgsql) ---"

if ! psql -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'planet_osm_line');" | grep -q 't'; then
    echo "Importiere OSM Geodaten..."
    psql -c "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pgrouting;"
    osm2pgsql --create --hstore-all --proj 4326 --slim "/osm_import/$PBF_FILENAME"
else
    echo "Geodaten bereits vorhanden. Überspringe osm2pgsql."
fi

echo "--- 3. SQL Logik anwenden (Views, Funktionen, Indizes) ---"

# Wir definieren die Reihenfolge explizit
SQL_FILES=("init.sql" "osm2po.sql" "routing.sql" "geocoding.sql" "network.sql" "trsp.sql")

for f in "${SQL_FILES[@]}"; do
    if [ -f "/sql/$f" ]; then
        echo "Anwenden von /sql/$f..."
        psql -f "/sql/$f"
    else
        echo "Warnung: Datei /sql/$f nicht gefunden!"
    fi
done

echo "--- SETUP ERFOLGREICH BEENDET ---"