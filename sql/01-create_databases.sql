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
    source INTEGER, 
    target INTEGER 
    length_m DOUBLE PRECISION,
    cost_car DOUBLE PRECISION,
    reverse_cost_car DOUBLE PRECISION,
    cost_bike DOUBLE PRECISION,
    reverse_cost_bike DOUBLE PRECISION,
    cost_walk DOUBLE PRECISION,
    reverse_cost_walk DOUBLE PRECISION
);

CREATE TABLE traffic_lights (
    osm_id BIGINT PRIMARY KEY,
    name TEXT,
    is_pedestrian_crossing_light BOOLEAN DEFAULT FALSE,
    tags hstore,
    geom GEOMETRY(Point, 4326)
);
