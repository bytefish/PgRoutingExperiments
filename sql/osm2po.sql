-- =============================================================
-- OSM2PO Indices
-- =============================================================
CREATE INDEX idx_osm2po_geom ON routing.osm2po_data USING GIST (geom_way);

-- =============================================================
-- CREATE VERTICES
-- =============================================================
SELECT pgr_createVerticesTable('routing.osm2po_data', 'geom_way', 'source', 'target');

CREATE INDEX IF NOT EXISTS idx_vertices_geom ON routing.osm2po_data_vertices_pgr USING GIST (the_geom);

ANALYZE routing.osm2po_data_vertices_pgr;