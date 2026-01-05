-- =============================================================
-- ROUTING FUNCTIONS
-- =============================================================
CREATE SCHEMA IF NOT EXISTS routing;

CREATE OR REPLACE FUNCTION routing.get_route(
    start_lon DOUBLE PRECISION, 
    start_lat DOUBLE PRECISION, 
    end_lon DOUBLE PRECISION, 
    end_lat DOUBLE PRECISION,
    transport_mode VARCHAR DEFAULT 'car'
)
RETURNS TABLE (
    seq INTEGER,
    osm_id BIGINT,
    osm_name TEXT,
    cost_time DOUBLE PRECISION,
    geom GEOMETRY(LineString, 4326)
) AS $$
DECLARE
    -- Map transport mode strings to bitwise flags (osm2po default bits)
    v_flag_bit INTEGER := CASE 
        WHEN transport_mode = 'car' THEN 1 
        WHEN transport_mode = 'bike' THEN 2 
        WHEN transport_mode = 'foot' THEN 4 
        ELSE 1 END;
    v_start_node BIGINT;
    v_end_node BIGINT;
BEGIN
    -- 1. Find the nearest node in the vertices table (Snapping)
    -- Uses the <-> operator for high-performance GIST index lookup
    SELECT id INTO v_start_node 
    FROM routing.osm2po_data_vertices_pgr
    ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(start_lon, start_lat), 4326) 
    LIMIT 1;

    SELECT id INTO v_end_node 
    FROM routing.osm2po_data_vertices_pgr
    ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(end_lon, end_lat), 4326) 
    LIMIT 1;

    -- 2. Exit if no start or end nodes are found
    IF v_start_node IS NULL OR v_end_node IS NULL THEN
        RETURN;
    END IF;

    -- 3. Execute Dijkstra routing on the edges
    RETURN QUERY
    SELECT 
        d.seq,
        e.osm_id,
        e.osm_name::TEXT,
        d.cost AS cost_time,
        e.geom_way AS geom
    FROM pgr_dijkstra(
        -- Filter edges based on transport mode bitwise flag
        format('SELECT id, source, target, cost, reverse_cost FROM routing.osm2po_data WHERE (flags & %L) > 0', v_flag_bit),
        v_start_node, 
        v_end_node, 
        TRUE -- directed routing (considers one-ways)
    ) AS d
    JOIN routing.osm2po_data e ON d.edge = e.id
    ORDER BY d.seq;
END;
$$ LANGUAGE plpgsql;