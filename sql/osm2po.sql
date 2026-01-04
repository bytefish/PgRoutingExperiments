-- =============================================================
-- OSM2PO Indices
-- =============================================================
CREATE INDEX idx_osm2po_geom ON routing.osm2po_data USING GIST (geom_way);