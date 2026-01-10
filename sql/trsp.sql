--================================================
-- TRSP (Traffic Lights)
--================================================

ALTER TABLE routing.osm2po_data_vertices_pgr 
    ADD COLUMN IF NOT EXISTS is_traffic_signal BOOLEAN DEFAULT FALSE;

UPDATE routing.osm2po_data_vertices_pgr v
SET is_traffic_signal = TRUE 
FROM public.planet_osm_point p
WHERE p.highway = 'traffic_signals' AND ST_DWithin(v.the_geom, p.way, 0.00003);

--================================================
-- TRSP (Manual Mapping)
--================================================
CREATE TABLE IF NOT EXISTS routing.osm2po_data_res (
    rid SERIAL PRIMARY KEY,
    from_edge INTEGER,
    to_cost FLOAT8,
    target_id INTEGER
);

TRUNCATE routing.osm2po_data_res;

-- Turn Restriction Mappings in OSM Data
INSERT INTO routing.osm2po_data_res (from_edge, target_id, to_cost)
SELECT 
    e1.id AS from_edge, 
    e2.id AS target_id, 
   (10.0 / 3600.0) AS to_cost -- 10 Second Penalty
FROM (
    SELECT 
        -- Index 1 (ID 'from'), Index 3 (ID 'to')
        regexp_replace(members[1], '\D', '', 'g')::bigint as osm_from_id,
        regexp_replace(members[3], '\D', '', 'g')::bigint as osm_to_id
    FROM public.planet_osm_rels
    WHERE 'restriction' = ANY(tags)
      
      AND members[2] = 'from'
      AND members[4] = 'to'
) rel
JOIN routing.osm2po_data e1 ON e1.osm_id = rel.osm_from_id
JOIN routing.osm2po_data e2 ON e2.osm_id = rel.osm_to_id
-- Make sure segments are connected
WHERE (e1.target = e2.source OR e1.source = e2.target OR e1.target = e2.target OR e1.source = e2.source);


 --================================================
-- TRSP (Routing Function)
--================================================
CREATE OR REPLACE FUNCTION routing.get_route_trsp(
    start_lon DOUBLE PRECISION, 
    start_lat DOUBLE PRECISION, 
    end_lon DOUBLE PRECISION, 
    end_lat DOUBLE PRECISION,
    transport_mode VARCHAR DEFAULT 'car',
    options JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
    seq INTEGER,
    osm_id BIGINT,
    osm_name TEXT,
    cost_time DOUBLE PRECISION,
    geom GEOMETRY(LineString, 4326)
) AS $$
DECLARE
    v_flag_bit INTEGER := CASE 
        WHEN transport_mode = 'car' THEN 1 
        WHEN transport_mode = 'bike' THEN 2 
        WHEN transport_mode = 'foot' THEN 4 
        ELSE 1 END;
    
    v_exclude_motorway BOOLEAN := COALESCE((options->>'exclude_motorway')::BOOLEAN, FALSE);
    v_extra_where TEXT := '';
    v_cost_calculation TEXT;
    v_start_node INTEGER;
    v_end_node INTEGER;
BEGIN
    IF v_exclude_motorway THEN
        v_extra_where := ' AND clazz NOT IN (11, 12)';
    END IF;

    v_cost_calculation := CASE 
        WHEN transport_mode = 'bike' THEN 
            'CASE WHEN clazz IN (51, 52) THEN (km/15.0)*0.7 ELSE (km/15.0) END'
        WHEN transport_mode = 'foot' THEN 
            'CASE WHEN clazz IN (53, 54, 52) THEN (km/4.5)*0.8 ELSE (km/4.5) END'
        ELSE 
            CASE 
                WHEN (options->>'avoid_motorway')::BOOLEAN AND NOT v_exclude_motorway THEN 
                    'CASE WHEN clazz IN (11, 12) THEN cost * 10.0 ELSE cost END'
                WHEN (options->>'optimize_consumption')::BOOLEAN THEN
                    'CASE WHEN clazz IN (11, 12) THEN cost * 1.5 WHEN clazz IN (13, 15, 21) THEN cost * 0.8 ELSE cost END'
                ELSE 'cost'
            END
    END;

    v_start_node := (
        SELECT v.id::integer 
        FROM routing.osm2po_data_vertices_pgr v
        WHERE EXISTS (
            SELECT 1 FROM routing.osm2po_data e 
            WHERE (e.source = v.id OR e.target = v.id) 
            AND (e.flags & v_flag_bit) > 0
            AND (NOT v_exclude_motorway OR e.clazz NOT IN (11, 12))
        )
        ORDER BY v.the_geom <-> ST_SetSRID(ST_MakePoint(start_lon, start_lat), 4326) LIMIT 1
    );

    v_end_node := (
        SELECT v.id::integer 
        FROM routing.osm2po_data_vertices_pgr v
        WHERE EXISTS (
            SELECT 1 FROM routing.osm2po_data e 
            WHERE (e.source = v.id OR e.target = v.id) 
            AND (e.flags & v_flag_bit) > 0
            AND (NOT v_exclude_motorway OR e.clazz NOT IN (11, 12))
        )
        ORDER BY v.the_geom <-> ST_SetSRID(ST_MakePoint(end_lon, end_lat), 4326) LIMIT 1
    );

    IF v_start_node IS NULL OR v_end_node IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT 
        d.seq, 
        e.osm_id, 
        e.osm_name::TEXT, 
        d.cost::float8 AS cost_time, 
        e.geom_way
    FROM pgr_trsp(
        format('SELECT id::int4, source::int4, target::int4, (%s)::float8 AS cost, (%s)::float8 AS reverse_cost FROM routing.osm2po_data WHERE (flags & %s) > 0 %s', 
            v_cost_calculation, replace(v_cost_calculation, 'cost', 'reverse_cost'), v_flag_bit, v_extra_where),
        v_start_node, 
        v_end_node, 
        TRUE, 
        TRUE,
        'SELECT to_cost::float8, target_id::int4, from_edge::int4, NULL::text AS via_path FROM routing.osm2po_data_res'
    ) AS d
    JOIN routing.osm2po_data e ON d.id2 = e.id 
    WHERE d.id2 != -1 
    ORDER BY d.seq;

END;
$$ LANGUAGE plpgsql;
