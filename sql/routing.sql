-- =============================================================
-- VIEW WITH CUSTOM COSTS
-- =============================================================
CREATE OR REPLACE VIEW public.road_network AS
SELECT 
    id,
    osm_name AS name,
    (cost * 3600) AS cost_car,
    (reverse_cost * 3600) AS reverse_cost_car,
    -- Deine Kosten-Logik für Bike/Walk (Beispiel)
    (km_way / 15.0 * 3600) AS cost_bike, 
    (km_way / 5.0 * 3600) AS cost_walk,
    geom_way AS geom,
    source,
    target,
    clazz AS road_type
FROM routing.osm2po_data;

-- =========================================================================
-- FUNCTIONS
-- =========================================================================
CREATE OR REPLACE FUNCTION get_route(
    mode TEXT, 
    start_lon FLOAT, start_lat FLOAT, 
    end_lon FLOAT, end_lat FLOAT,
    bbox_buffer FLOAT DEFAULT 0.05 -- Etwas größerer Puffer für osm2po empfohlen
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
    walking_speed_mps FLOAT := 1.38; -- ca. 5 km/h
BEGIN
    -- 1. Configuration (Nutzt nun die View-Spaltennamen aus Schritt zuvor)
    CASE mode
        WHEN 'car' THEN cost_col := 'cost_car'; rev_cost_col := 'reverse_cost_car'; is_directed := true;
        WHEN 'bike' THEN cost_col := 'cost_bike'; rev_cost_col := 'cost_bike'; is_directed := true;
        WHEN 'walk' THEN cost_col := 'cost_walk'; rev_cost_col := 'cost_walk'; is_directed := false;
        ELSE RAISE EXCEPTION 'Invalid mode.';
    END CASE;

    -- 2. Precise Snapping: Find the exact point on the nearest ALLOWED road
    SELECT ST_SetSRID(ST_LineInterpolatePoint(rn.geom, ST_LineLocatePoint(rn.geom, ST_SetSRID(ST_Point(start_lon, start_lat), 4326))), 4326)
    INTO start_snap_pt 
    FROM road_network rn 
    WHERE 
        CASE 
            WHEN mode IN ('bike', 'walk') THEN rn.road_type > 15 -- Keine Autobahnen/Kraftfahrstraßen
            ELSE true 
        END
    ORDER BY rn.geom <-> ST_SetSRID(ST_Point(start_lon, start_lat), 4326) 
    LIMIT 1;

    SELECT ST_SetSRID(ST_LineInterpolatePoint(rn.geom, ST_LineLocatePoint(rn.geom, ST_SetSRID(ST_Point(end_lon, end_lat), 4326))), 4326)
    INTO end_snap_pt 
    FROM road_network rn 
    WHERE 
        CASE 
            WHEN mode IN ('bike', 'walk') THEN rn.road_type > 15 
            ELSE true 
        END
    ORDER BY rn.geom <-> ST_SetSRID(ST_Point(end_lon, end_lat), 4326) 
    LIMIT 1;
    
    -- 3. Dynamic BBox logic
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
            ARRAY(SELECT id FROM routing.osm2po_data_vertices ORDER BY the_geom <-> start_snap_pt LIMIT 5),
            ARRAY(SELECT id FROM routing.osm2po_data_vertices ORDER BY the_geom <-> end_snap_pt LIMIT 5),
            directed := is_directed
        )
    ),
    best_route_segments AS (
        SELECT r.* FROM route_raw r
        WHERE (r.start_vid, r.end_vid) IN (
            SELECT start_vid, end_vid FROM route_raw 
            GROUP BY start_vid, end_vid ORDER BY SUM(cost) ASC LIMIT 1
        )
    ),
    mapped_route AS (
        SELECT 
            r.seq AS m_seq,
            COALESCE(rn.name, nearby.name || ' (Access)', 'Street') as m_name,
            rn.road_type::TEXT as m_type,
            r.cost::FLOAT as m_seconds,
            rn.geom as m_geom
        FROM best_route_segments r
        JOIN road_network rn ON r.edge = rn.id
        LEFT JOIN LATERAL (
            SELECT name FROM road_network parent
            WHERE (rn.name IS NULL OR rn.name LIKE 'Unnamed%')
              AND parent.name IS NOT NULL
              AND parent.name NOT LIKE 'Unnamed%'
              AND parent.road_type > 20 
              AND parent.geom && ST_Expand(rn.geom, 0.0005)
              AND ST_DWithin(rn.geom, parent.geom, 0.0002)
            ORDER BY rn.geom <-> parent.geom ASC LIMIT 1
        ) nearby ON TRUE
        ORDER BY r.seq
    ),
    conn_start(c_seq, c_name, c_type, c_seconds, c_geom) AS (
        SELECT 0, 'Start Access'::TEXT, 'connection'::TEXT, 
               (ST_DistanceSphere(ST_SetSRID(ST_Point(start_lon, start_lat), 4326), start_snap_pt) / walking_speed_mps)::FLOAT,
               ST_MakeLine(ST_SetSRID(ST_Point(start_lon, start_lat), 4326), start_snap_pt)
        UNION ALL
        SELECT 1, 'Entry'::TEXT, 'connection'::TEXT,
               (ST_DistanceSphere(start_snap_pt, ST_ClosestPoint((SELECT m_geom FROM mapped_route ORDER BY m_seq LIMIT 1), start_snap_pt)) / walking_speed_mps)::FLOAT,
               ST_MakeLine(start_snap_pt, ST_ClosestPoint((SELECT m_geom FROM mapped_route ORDER BY m_seq LIMIT 1), start_snap_pt))
        WHERE EXISTS (SELECT 1 FROM mapped_route)
    ),
    conn_end(c_seq, c_name, c_type, c_seconds, c_geom) AS (
        SELECT (SELECT MAX(m_seq) + 3 FROM mapped_route), 'Exit'::TEXT, 'connection'::TEXT,
               (ST_DistanceSphere(ST_ClosestPoint((SELECT m_geom FROM mapped_route ORDER BY m_seq DESC LIMIT 1), end_snap_pt), end_snap_pt) / walking_speed_mps)::FLOAT,
               ST_MakeLine(ST_ClosestPoint((SELECT m_geom FROM mapped_route ORDER BY m_seq DESC LIMIT 1), end_snap_pt), end_snap_pt)
        WHERE EXISTS (SELECT 1 FROM mapped_route)
        UNION ALL
        SELECT (SELECT COALESCE(MAX(m_seq), 0) + 4 FROM mapped_route), 'Destination'::TEXT, 'connection'::TEXT,
               (ST_DistanceSphere(end_snap_pt, ST_SetSRID(ST_Point(end_lon, end_lat), 4326)) / walking_speed_mps)::FLOAT,
               ST_MakeLine(end_snap_pt, ST_SetSRID(ST_Point(end_lon, end_lat), 4326))
    )
    SELECT c_seq, c_name, c_type, c_seconds, c_geom FROM conn_start
    UNION ALL
    SELECT m_seq + 2, m_name, m_type, m_seconds, m_geom FROM mapped_route
    UNION ALL
    SELECT c_seq, c_name, c_type, c_seconds, c_geom FROM conn_end
    ORDER BY 1;
END;
$$ LANGUAGE plpgsql STABLE;
