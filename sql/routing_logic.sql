-- =============================================================
-- PREPARATION
-- =============================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE EXTENSION IF NOT EXISTS hstore;

-- =============================================================
-- CREATE TABLES
-- =============================================================
DO $$ BEGIN RAISE NOTICE 'Creating Tables...'; END $$;

DROP TABLE IF EXISTS road_network CASCADE;
CREATE TABLE road_network (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT,
    road_type TEXT,
    name TEXT,
    ref TEXT,
    tags hstore,
    speed_limit_kmh INTEGER,
    geom GEOMETRY(LineString, 4326),
    source INTEGER,
    target INTEGER,
    length_m DOUBLE PRECISION,
    cost_car DOUBLE PRECISION, reverse_cost_car DOUBLE PRECISION,
    cost_bike DOUBLE PRECISION, reverse_cost_bike DOUBLE PRECISION,
    cost_walk DOUBLE PRECISION, reverse_cost_walk DOUBLE PRECISION
);

-- =============================================================
-- IMPORT OSM DATA FOR ROUTING
-- =============================================================
DO $$ BEGIN RAISE NOTICE 'Splitting geometries at intersections...'; END $$;

INSERT INTO road_network (osm_id, name, ref, tags, road_type, speed_limit_kmh, geom, length_m)
SELECT 
    osm_id, name, ref, tags,
    CASE
        WHEN highway IN ('motorway', 'motorway_link') THEN 'Motorway'
        WHEN highway IN ('trunk', 'trunk_link') THEN 'Trunk Road'
        WHEN highway IN ('primary', 'primary_link') THEN 'Primary Road'
        WHEN highway IN ('secondary', 'secondary_link') THEN 'Secondary Road'
        WHEN highway IN ('tertiary', 'tertiary_link') THEN 'Tertiary Road'
        WHEN highway = 'residential' THEN 'Residential'
        WHEN highway = 'living_street' THEN 'Living Street'
        WHEN highway = 'unclassified' THEN 'Unclassified'
        WHEN highway = 'service' THEN 'Service Road'
        WHEN highway = 'pedestrian' THEN 'Pedestrian Zone'
        WHEN highway = 'footway' THEN 'Footway'
        WHEN highway = 'cycleway' THEN 'Cycleway'
        WHEN highway = 'path' THEN 'Path'
        WHEN highway = 'steps' THEN 'Steps'
        WHEN highway = 'track' THEN 'Track'
        ELSE 'Other'
    END,
    CASE
        WHEN tags -> 'maxspeed' ~ '^[0-9]+$' THEN CAST(tags -> 'maxspeed' AS INTEGER)
        WHEN tags -> 'maxspeed' = 'DE:urban' THEN 50
        WHEN tags -> 'maxspeed' = 'DE:rural' THEN 100
        ELSE NULL
    END,
    sub.geom,
    ST_Length(sub.geom::geography)
FROM (
    -- Noding inside sub-query
    SELECT osm_id, name, ref, tags, highway, 
           (ST_Dump(ST_Node(ST_Transform(way, 4326)))).geom 
    FROM planet_osm_line
    WHERE highway IS NOT NULL 
      AND highway NOT IN ('proposed', 'construction', 'abandoned', 'platform')
) sub;

-- =============================================================
-- INDEXING & TOPOLOGY
-- =============================================================
DO $$ BEGIN RAISE NOTICE 'Creating Indexes...'; END $$;

CREATE INDEX idx_rn_road_type ON road_network(road_type);
CREATE INDEX idx_rn_geom ON road_network USING GIST(geom);
CREATE INDEX idx_rn_endpoint ON road_network USING GIST (ST_EndPoint(geom));
CREATE INDEX idx_rn_oneway ON road_network ((tags -> 'oneway'));

DO $$ BEGIN RAISE NOTICE 'Creating Topology...'; END $$;

SELECT pgr_createTopology('road_network', 0.000001, 'geom', 'id');

-- =========================================================================
-- COST CALCULATIONS (GENERAL)
-- =========================================================================
DO $$ BEGIN RAISE NOTICE 'Calculating Costs and Applying General Preferences...'; END $$;

-- Default speeds for safety
UPDATE road_network SET speed_limit_kmh = CASE 
    WHEN speed_limit_kmh IS NULL OR speed_limit_kmh <= 0 THEN 
        CASE 
            WHEN road_type = 'Motorway' THEN 130
            WHEN road_type IN ('Trunk Road', 'Primary Road') THEN 100
            WHEN road_type IN ('Secondary Road', 'Tertiary Road', 'Residential', 'Unclassified') THEN 50
            ELSE 20 
        END
    ELSE speed_limit_kmh
END;

UPDATE road_network SET
    -- CAR: Strict exclusion of non-motorized paths. Penalty for Other/Service.
    cost_car = CASE 
        WHEN road_type IN ('Footway', 'Steps', 'Pedestrian Zone', 'Path', 'Cycleway') THEN -1 
        WHEN road_type = 'Track' AND (tags -> 'tracktype') NOT IN ('grade1') THEN -1
        WHEN road_type IN ('Other', 'Service Road', 'Unclassified') THEN (length_m / (20.0/3.6)) * 2.5
        ELSE length_m / (NULLIF(speed_limit_kmh, 0) / 3.6) 
    END,
    -- BIKE: Münster preferences
    cost_bike = CASE 
        WHEN road_type IN ('Motorway', 'Steps') THEN -1
        ELSE (length_m / (15.0 / 3.6)) * CASE 
                WHEN road_type = 'Cycleway' THEN 0.7 
                WHEN road_type IN ('Trunk Road', 'Primary Road') THEN 5.0
                ELSE 1.0 END
    END,
    -- WALK: Focus on safety and shortcuts
    cost_walk = CASE 
        WHEN road_type IN ('Motorway', 'Trunk Road') THEN -1
        ELSE (length_m / (5.0 / 3.6)) * CASE 
                WHEN road_type IN ('Footway', 'Path', 'Pedestrian Zone') THEN 0.7 
                WHEN road_type = 'Steps' THEN 1.5
                ELSE 1.0 END
    END;

-- =========================================================================
-- COST CALCULATIONS (SPECIFIC)
-- =========================================================================
DO $$ BEGIN RAISE NOTICE 'Calculating Costs FOR "Münster"...'; END $$;

UPDATE road_network SET 
    -- 30% extra discount for bikes on the Promenade
    cost_bike = cost_bike * 0.7,
    -- 20% extra discount for pedestrians on the Promenade
    cost_walk = cost_walk * 0.8
WHERE name ILIKE '%Promenade%';

-- =========================================================================
-- TRAFFIC LIGHTS & ONEWAYS
-- =========================================================================
-- Apply 20s penalty to any edge ending at a traffic signal
UPDATE road_network rn SET 
    cost_car = cost_car + 20, cost_bike = cost_bike + 15, cost_walk = cost_walk + 15
FROM planet_osm_point tl
WHERE tl.highway = 'traffic_signals' AND ST_DWithin(ST_EndPoint(rn.geom), ST_Transform(tl.way, 4326), 0.00002);

-- Set reverse costs and catch all remaining NULLs
UPDATE road_network SET 
    reverse_cost_car = CASE WHEN (tags -> 'oneway') IN ('yes', '1', 'true') THEN -1 ELSE cost_car END,
    reverse_cost_bike = cost_bike,
    reverse_cost_walk = cost_walk;

UPDATE road_network SET 
    cost_car = COALESCE(cost_car, -1), reverse_cost_car = COALESCE(reverse_cost_car, -1),
    cost_bike = COALESCE(cost_bike, -1), reverse_cost_bike = COALESCE(reverse_cost_bike, -1),
    cost_walk = COALESCE(cost_walk, -1), reverse_cost_walk = COALESCE(reverse_cost_walk, -1);

DO $$ BEGIN RAISE NOTICE 'Road network is fully connected and ready.'; END $$;

-- =========================================================================
-- FUNCTIONS
-- =========================================================================
CREATE OR REPLACE FUNCTION get_route(
    mode TEXT, 
    start_lon FLOAT, start_lat FLOAT, 
    end_lon FLOAT, end_lat FLOAT,
    bbox_buffer FLOAT DEFAULT 0.02
)
RETURNS TABLE (
    out_seq INTEGER, 
    out_name TEXT, 
    out_type TEXT, 
    out_seconds FLOAT, 
    out_geom GEOMETRY
) AS $$
DECLARE
    cost_col TEXT;
    rev_cost_col TEXT;
    is_directed BOOLEAN;
    bbox_filter TEXT;
    start_snap_pt GEOMETRY;
    end_snap_pt GEOMETRY;
    walking_speed_mps FLOAT := 1.38; -- approx 5 km/h
BEGIN
    -- 1. Configuration
    CASE mode
        WHEN 'car' THEN cost_col := 'cost_car'; rev_cost_col := 'reverse_cost_car'; is_directed := true;
        WHEN 'bike' THEN cost_col := 'cost_bike'; rev_cost_col := 'reverse_cost_bike'; is_directed := true;
        WHEN 'walk' THEN cost_col := 'cost_walk'; rev_cost_col := 'cost_walk'; is_directed := false;
        ELSE RAISE EXCEPTION 'Invalid mode.';
    END CASE;

    -- 2. Precise Snapping: Find the exact point on the nearest road
    SELECT ST_SetSRID(ST_LineInterpolatePoint(rn.geom, ST_LineLocatePoint(rn.geom, ST_SetSRID(ST_Point(start_lon, start_lat), 4326))), 4326)
    INTO start_snap_pt FROM road_network rn ORDER BY rn.geom <-> ST_SetSRID(ST_Point(start_lon, start_lat), 4326) LIMIT 1;

    SELECT ST_SetSRID(ST_LineInterpolatePoint(rn.geom, ST_LineLocatePoint(rn.geom, ST_SetSRID(ST_Point(end_lon, end_lat), 4326))), 4326)
    INTO end_snap_pt FROM road_network rn ORDER BY rn.geom <-> ST_SetSRID(ST_Point(end_lon, end_lat), 4326) LIMIT 1;

    -- 3. Dynamic Bounding Box (BBOX) logic
    bbox_filter := format(
        'geom && ST_Expand(ST_MakeEnvelope(%L, %L, %L, %L, 4326), %L)',
        LEAST(start_lon, end_lon), LEAST(start_lat, end_lat),
        GREATEST(start_lon, end_lon), GREATEST(start_lat, end_lat),
        bbox_buffer
    );

    RETURN QUERY
    WITH route_raw AS (
        SELECT * FROM pgr_dijkstra(
            format('SELECT id, source, target, %I AS cost, %I AS reverse_cost FROM road_network WHERE %I > 0 AND %s', 
                   cost_col, rev_cost_col, cost_col, bbox_filter),
            ARRAY(SELECT id FROM road_network_vertices_pgr ORDER BY the_geom <-> start_snap_pt LIMIT 5),
            ARRAY(SELECT id FROM road_network_vertices_pgr ORDER BY the_geom <-> end_snap_pt LIMIT 5),
            directed := is_directed
        )
    ),
    -- Your logic: Find the absolute best combination from the 5x5 possible node pairs
    best_route_segments AS (
        SELECT r.* FROM route_raw r
        WHERE (r.start_vid, r.end_vid) IN (
            SELECT start_vid, end_vid FROM route_raw 
            GROUP BY start_vid, end_vid ORDER BY SUM(cost) ASC LIMIT 1
        )
    ),
    -- Mapping road data and addressing unnamed streets
    mapped_route AS (
        SELECT 
            r.seq AS m_seq,
            COALESCE(rn.name, nearby.name || ' (Access)', initcap(rn.road_type)) as m_name,
            rn.road_type as m_type,
            r.cost::FLOAT as m_seconds,
            rn.geom as m_geom
        FROM best_route_segments r
        JOIN road_network rn ON r.edge = rn.id
        LEFT JOIN LATERAL (
            -- Sub-query to find parent road names for unnamed service/access roads
            SELECT name FROM road_network parent
            WHERE (rn.name IS NULL OR rn.name LIKE 'Unnamed%')
              AND parent.name NOT LIKE 'Unnamed%'
              AND parent.road_type NOT IN ('Cycleway', 'Footway', 'Path')
              AND parent.geom && ST_Expand(rn.geom, 0.0005)
              AND ST_DWithin(rn.geom, parent.geom, 0.0002)
            ORDER BY rn.geom <-> parent.geom ASC LIMIT 1
        ) nearby ON TRUE
        ORDER BY r.seq
    ),
    -- 4. Access Segments: Connect user click points to the road network
    conn_start(c_seq, c_name, c_type, c_seconds, c_geom) AS (
        -- Connection from Click Start to Snapped Point + Snapped Point to first Routing Node
        SELECT 0, 'Start Access'::TEXT, 'connection'::TEXT, 
               (ST_DistanceSphere(ST_SetSRID(ST_Point(start_lon, start_lat), 4326), start_snap_pt) / walking_speed_mps)::FLOAT,
               ST_MakeLine(ST_SetSRID(ST_Point(start_lon, start_lat), 4326), start_snap_pt)
        UNION ALL
        SELECT 1, 'Entry'::TEXT, 'connection'::TEXT,
               (ST_DistanceSphere(start_snap_pt, ST_StartPoint((SELECT m_geom FROM mapped_route LIMIT 1))) / walking_speed_mps)::FLOAT,
               ST_MakeLine(start_snap_pt, ST_StartPoint((SELECT m_geom FROM mapped_route LIMIT 1)))
        WHERE EXISTS (SELECT 1 FROM mapped_route)
    ),
    conn_end(c_seq, c_name, c_type, c_seconds, c_geom) AS (
        -- Connection from last Routing Node to Snapped Point + Snapped Point to Click Destination
        SELECT (SELECT MAX(m_seq) + 3 FROM mapped_route), 'Exit'::TEXT, 'connection'::TEXT,
               (ST_DistanceSphere(ST_EndPoint((SELECT m_geom FROM mapped_route ORDER BY m_seq DESC LIMIT 1)), end_snap_pt) / walking_speed_mps)::FLOAT,
               ST_MakeLine(ST_EndPoint((SELECT m_geom FROM mapped_route ORDER BY m_seq DESC LIMIT 1)), end_snap_pt)
        WHERE EXISTS (SELECT 1 FROM mapped_route)
        UNION ALL
        SELECT (SELECT MAX(m_seq) + 4 FROM mapped_route), 'Destination'::TEXT, 'connection'::TEXT,
               (ST_DistanceSphere(end_snap_pt, ST_SetSRID(ST_Point(end_lon, end_lat), 4326)) / walking_speed_mps)::FLOAT,
               ST_MakeLine(end_snap_pt, ST_SetSRID(ST_Point(end_lon, end_lat), 4326))
    )
    -- 5. Combine final result
    SELECT c_seq, c_name, c_type, c_seconds, c_geom FROM conn_start
    UNION ALL
    SELECT m_seq + 2, m_name, m_type, m_seconds, m_geom FROM mapped_route
    UNION ALL
    SELECT c_seq, c_name, c_type, c_seconds, c_geom FROM conn_end
    ORDER BY 1;
END;
$$ LANGUAGE plpgsql STABLE;