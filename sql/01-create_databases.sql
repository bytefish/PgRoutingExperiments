-----------------------------------------------------
-- Create Extensions
-----------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE EXTENSION IF NOT EXISTS hstore;

-----------------------------------------------------
-- Create tables
-----------------------------------------------------
DROP TABLE IF EXISTS road_segments;
DROP TABLE IF EXISTS traffic_lights;

CREATE TABLE road_segments (
    osm_id BIGINT PRIMARY KEY,
    osm_type TEXT,
    road_type TEXT,
    name TEXT,
    ref TEXT,
    speed_limit_kmh INTEGER,
    tags hstore,
    geom GEOMETRY(LineString, 4326),
    source INTEGER, -- Wird von pgr_createTopology befüllt
    target INTEGER  -- Wird von pgr_createTopology befüllt
);

CREATE TABLE traffic_lights (
    osm_id BIGINT PRIMARY KEY,
    name TEXT,
    is_pedestrian_crossing_light BOOLEAN DEFAULT FALSE,
    tags hstore,
    geom GEOMETRY(Point, 4326)
);
-----------------------------------------------------
-- Migrate from raw OSM to our Routing data tables
-----------------------------------------------------
INSERT INTO road_segments (osm_id, osm_type, name, ref, road_type, speed_limit_kmh, tags, geom)
SELECT
    osm_id AS osm_id,
    highway AS osm_type,
    name,
    ref,
    CASE
        WHEN highway = 'motorway' THEN 'Autobahn'
        WHEN highway = 'trunk' THEN 'Bundesstrasse'
        WHEN highway = 'primary' THEN 'Landesstrasse'
        WHEN highway = 'secondary' THEN 'Landesstrasse'
        WHEN highway = 'tertiary' THEN 'Stadtstrasse'
        WHEN highway = 'residential' THEN 'Residential'
        WHEN highway = 'unclassified' THEN 'Unclassified'
        WHEN highway = 'service' THEN 'Service Road'
        ELSE 'Other Road'
    END AS road_type,
    CASE
        WHEN tags -> 'maxspeed' ~ '^[0-9]+$' THEN CAST(tags -> 'maxspeed' AS INTEGER)
        WHEN tags -> 'maxspeed' IN ('walk', 'inf') THEN NULL
        WHEN tags -> 'maxspeed' = 'DE:urban' THEN 50
        WHEN tags -> 'maxspeed' = 'DE:rural' THEN 100
        ELSE NULL
    END AS speed_limit_kmh,
    tags,
    ST_Transform(way, 4326) AS geom
FROM
    planet_osm_line
WHERE
    highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential', 'unclassified', 'service')
    AND NOT (tunnel = 'yes' AND highway = 'footway')
    AND NOT (bridge = 'yes' AND highway = 'footway');

-----------------------------------------------------
-- Estimate missing Speed Limits
-----------------------------------------------------
UPDATE road_segments
SET speed_limit_kmh = CASE
    WHEN road_type = 'Autobahn' AND speed_limit_kmh IS NULL THEN 130
    WHEN road_type IN ('Bundesstrasse', 'Landesstrasse', 'Unclassified') AND speed_limit_kmh IS NULL THEN 100
    WHEN road_type IN ('Stadtstrasse', 'Residential', 'Service Road') AND speed_limit_kmh IS NULL THEN 50
    ELSE speed_limit_kmh
END
WHERE speed_limit_kmh IS NULL;

-----------------------------------------------------
-- Insert Traffic Light data
-----------------------------------------------------
INSERT INTO traffic_lights (osm_id, name, is_pedestrian_crossing_light, tags, geom)
SELECT
    osm_id AS id,
    name,
    CASE
        WHEN tags -> 'crossing' = 'traffic_signals' THEN TRUE
        ELSE FALSE
    END AS is_pedestrian_crossing_light,
    tags,
    ST_Transform(way, 4326) AS geom
FROM
    planet_osm_point
WHERE
    highway = 'traffic_signals'
    OR (tags ? 'crossing' AND tags -> 'crossing' = 'traffic_signals');

-----------------------------------------------------
-- Remove duplicates in the Traffic Light Data
-----------------------------------------------------
DELETE FROM traffic_lights
WHERE ctid IN (
    SELECT ctid FROM (
        SELECT
            ctid,
            ROW_NUMBER() OVER (PARTITION BY osm_id ORDER BY osm_id) as rn
        FROM traffic_lights
    ) t WHERE t.rn > 1
);

-----------------------------------------------------
-- Create indices for faster lookups
-----------------------------------------------------
CREATE INDEX idx_road_segments_geom ON road_segments USING GIST(geom);
CREATE INDEX idx_road_segments_geom_geog ON road_segments USING gist((geom::geography));
CREATE INDEX idx_road_segments_source ON road_segments(source);
CREATE INDEX idx_road_segments_target ON road_segments(target);

CREATE INDEX idx_traffic_lights_geom ON traffic_lights USING GIST(geom);
CREATE INDEX idx_traffic_lights_geom_geog ON traffic_lights USING gist((geom::geography));

-----------------------------------------------------
-- Creates the pgRouting Topology
-----------------------------------------------------
SELECT pgr_createTopology('road_segments', 0.00001, 'geom', 'osm_id');