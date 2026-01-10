CREATE OR REPLACE FUNCTION routing.get_route(
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
    -- OSM2PO Bit-Flags (1=Car, 2=Bike, 4=Foot)
    v_flag_bit INTEGER := CASE 
        WHEN transport_mode = 'car' THEN 1 
        WHEN transport_mode = 'bike' THEN 2 
        WHEN transport_mode = 'foot' THEN 4 
        ELSE 1 END;
    
    -- Average Speed for the Transport Modes
    v_default_speed FLOAT := CASE 
        WHEN transport_mode = 'bike' THEN 15.0 
        WHEN transport_mode = 'foot' THEN 4.5 
        ELSE NULL END; 

    v_extra_where TEXT := '';
    v_cost_calculation TEXT;
    
    v_start_node BIGINT;
    v_end_node BIGINT;
BEGIN
    
    IF (options->>'exclude_motorway')::BOOLEAN THEN
        v_extra_where := v_extra_where || ' AND clazz NOT IN (11, 12)';
    END IF;

    v_cost_calculation := CASE 
        WHEN transport_mode = 'bike' THEN 
            'CASE 
                WHEN clazz IN (51, 52) THEN (km / 15.0) * 0.7 
                WHEN clazz IN (15, 21) THEN (km / 15.0) * 3.0 
                WHEN clazz = 56 THEN (km / 15.0) * 10.0 
                ELSE (km / 15.0) 
             END'
        
        WHEN transport_mode = 'foot' THEN 
            'CASE 
                WHEN clazz IN (53, 54, 52) THEN (km / 4.5) * 0.8 
                WHEN clazz IN (15, 21, 31) THEN (km / 4.5) * 5.0 
                ELSE (km / 4.5) 
             END'

        ELSE 
            CASE 
                WHEN (options->>'exclude_motorway')::BOOLEAN THEN 'cost' -- Schon in WHERE gefiltert
                WHEN (options->>'avoid_motorway')::BOOLEAN THEN 'CASE WHEN clazz IN (11, 12) THEN cost * 10.0 ELSE cost END'
                
                WHEN (options->>'optimize_consumption')::BOOLEAN THEN
                    'CASE 
                        WHEN clazz IN (11, 12) THEN cost * 1.5    -- Autobahn (Luftwiderstand)
                        WHEN clazz IN (13, 15, 21) THEN cost * 0.8 -- Landstraßen (Optimaler Bereich)
                        WHEN clazz IN (43, 44) THEN cost * 1.3    -- Stadt (Stop-and-Go)
                        ELSE cost 
                     END'
                ELSE 'cost'
            END
    END;

    SELECT id INTO v_start_node FROM routing.osm2po_data_vertices_pgr
    ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(start_lon, start_lat), 4326) LIMIT 1;

    SELECT id INTO v_end_node FROM routing.osm2po_data_vertices_pgr
    ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(end_lon, end_lat), 4326) LIMIT 1;

    IF v_start_node IS NULL OR v_end_node IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT 
        d.seq, e.osm_id, e.osm_name::TEXT, d.cost, e.geom_way
    FROM pgr_dijkstra(
        format(
            'SELECT id, source, target, 
            (%s) AS cost,
            (%s) AS reverse_cost 
            FROM routing.osm2po_data 
            WHERE (flags & %s) > 0 %s', 
            v_cost_calculation, 
            replace(v_cost_calculation, 'cost', 'reverse_cost'), 
            v_flag_bit, 
            v_extra_where
        ),
        v_start_node, v_end_node, TRUE 
    ) AS d
    JOIN routing.osm2po_data e ON d.edge = e.id
    ORDER BY d.seq;
END;
$$ LANGUAGE plpgsql;