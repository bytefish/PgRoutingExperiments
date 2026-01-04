// Erweiterung für den MapService (angular 18+)
import { Injectable, signal, NgZone, inject } from '@angular/core';
import * as maplibregl from 'maplibre-gl';

@Injectable({ providedIn: 'root' })
export class MapService {
  private readonly zone = inject(NgZone);
  private map?: maplibregl.Map;

  // Signale für die ausgewählten Punkte
  readonly startPoint = signal<[number, number] | null>(null);
  readonly endPoint = signal<[number, number] | null>(null);

  private startMarker?: maplibregl.Marker;
  private endMarker?: maplibregl.Marker;

  buildMap(container: HTMLElement, style: any, center: any, zoom: any): void {
    this.zone.runOutsideAngular(() => {
      this.map = new maplibregl.Map({
        container, style, center, zoom
      });

      this.map.on('load', () => {
        this.setupRoutingLayers();
        this.setupBBoxLayer();
      });

      // Klick-Event zur Auswahl der Punkte
      this.map.on('click', (e) => {
        this.zone.run(() => this.handleMapClick(e.lngLat));
      });
    });
  }

  private handleMapClick(lngLat: maplibregl.LngLat) {
    const coords: [number, number] = [lngLat.lng, lngLat.lat];

    if (!this.startPoint()) {
      // First Click = Starting Point
      this.startPoint.set(coords);
      this.startMarker = new maplibregl.Marker({ color: '#2ecc71' })
        .setLngLat(lngLat)
        .addTo(this.map!);
    } else if (!this.endPoint()) {
      // Second Click = End Point
      this.endPoint.set(coords);
      this.endMarker = new maplibregl.Marker({ color: '#e74c3c' })
        .setLngLat(lngLat)
        .addTo(this.map!);
    } else {
      // Third Click = Reset Points
      this.resetRouting();
      this.handleMapClick(lngLat);
    }
  }

  resetRouting() {
    this.startPoint.set(null);
    this.endPoint.set(null);
    this.startMarker?.remove();
    this.endMarker?.remove();
    // Remove from Route
    const source = this.map?.getSource('route') as maplibregl.GeoJSONSource;
    source?.setData({ type: 'FeatureCollection', features: [] });
  }

  private setupRoutingLayers(): void {
    if (!this.map) return;

    // Add source for the routing data
    this.map.addSource('route', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    });

    // Add the visual line layer
    this.map.addLayer({
      id: 'route-line',
      type: 'line',
      source: 'route',
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: {
        'line-color': '#3887be',
        'line-width': 5,
        'line-opacity': 0.75
      }
    });
  }

  toggleBBoxVisibility(visible: boolean) {
    if (!this.map || !this.map.getLayer('bbox-layer')) return;

    const visibility = visible ? 'visible' : 'none';

    this.map.setLayoutProperty('bbox-layer', 'visibility', visibility);
  }

  private setupBBoxLayer() {
    if (!this.map) return;

    this.map.addSource('debug-bbox', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    });

    this.map.addLayer({
      id: 'bbox-layer',
      type: 'fill',
      source: 'debug-bbox',
      layout: {
        'visibility': 'none'
      },
      paint: {
        'fill-color': '#ff0000',
        'fill-opacity': 0.1,
        'fill-outline-color': '#ff0000'
      }
    });
  }

  showDebugBBox(bbox: any) {
    const source = this.map?.getSource('debug-bbox') as maplibregl.GeoJSONSource;
    if (!source) return;

    // Erstelle ein Polygon aus den 4 Ecken
    const polygon = {
      type: 'Feature',
      geometry: {
        type: 'Polygon',
        coordinates: [[
          [bbox.minLon, bbox.minLat],
          [bbox.maxLon, bbox.minLat],
          [bbox.maxLon, bbox.maxLat],
          [bbox.minLon, bbox.maxLat],
          [bbox.minLon, bbox.minLat] // Polygon schließen
        ]]
      }
    };

    source.setData({ type: 'FeatureCollection', features: [polygon as any] });
  }

  /**
   * Updates the map with a new GeoJSON route
   */
  setRoute(geojson: any): void {
    if (!this.map) return;

    const source = this.map?.getSource('route') as maplibregl.GeoJSONSource;
    if (!source || !geojson.features.length) return;

    source.setData(geojson);

    // Calculate bounds to focus the route
    const bounds = new maplibregl.LngLatBounds();
    geojson.features.forEach((feature: any) => {
      if (feature.geometry.type === 'LineString') {
        feature.geometry.coordinates.forEach((coord: [number, number]) => {
          bounds.extend(coord);
        });
      }
    });

    this.map?.fitBounds(bounds, { padding: 40, duration: 1000 });
  }

  destroyMap(): void {
    if (this.map) {
      this.map.remove();
    }
  }
}
