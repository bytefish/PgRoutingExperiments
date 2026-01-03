@echo off

:: Licensed under the MIT license. See LICENSE file in the project root for full license information.

:: OSM2PGSQL Executable Executable
set OSM2PGSQL_EXECUTABLE="C:\Users\philipp\source\repos\bytefish\osm2pgsql-latest-x64\osm2pgsql-bin\osm2pgsql.exe"

:: Parameters
set OSM_STYLE="C:\Users\philipp\source\repos\bytefish\osm2pgsql-latest-x64\osm2pgsql-bin\default.style"
set OSM_PBF="C:\Users\philipp\Downloads\muenster-regbez-latest.osm.pbf"

SET DB_USER=postgis
SET DB_PASSWD=postgis
set DB_NAME=routing
set DB_HOST=localhost
set DB_PORT=5432
SET CACHE_FILE="./flat_nodes.cache"

:: Run OSM Import
%OSM2PGSQL_EXECUTABLE% -S %OSM_STYLE% -d %DB_NAME% -U postgis -W -H %DB_HOST% -P %DB_PORT% -s -C 2000 --flat-nodes=%CACHE_FILE% --hstore %OSM_PBF%
