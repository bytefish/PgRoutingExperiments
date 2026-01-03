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

      this.map.on('load', () => this.setupRoutingLayers());

      // Klick-Event zur Auswahl der Punkte
      this.map.on('click', (e) => {
        this.zone.run(() => this.handleMapClick(e.lngLat));
      });
    });
  }

  private handleMapClick(lngLat: maplibregl.LngLat) {
    const coords: [number, number] = [lngLat.lng, lngLat.lat];

    if (!this.startPoint()) {
      // Erster Klick = Startpunkt
      this.startPoint.set(coords);
      this.startMarker = new maplibregl.Marker({ color: '#2ecc71' })
        .setLngLat(lngLat)
        .addTo(this.map!);
    } else if (!this.endPoint()) {
      // Zweiter Klick = Endpunkt
      this.endPoint.set(coords);
      this.endMarker = new maplibregl.Marker({ color: '#e74c3c' })
        .setLngLat(lngLat)
        .addTo(this.map!);
    } else {
      // Dritter Klick = Reset und neuer Start
      this.resetRouting();
      this.handleMapClick(lngLat);
    }
  }

  resetRouting() {
    this.startPoint.set(null);
    this.endPoint.set(null);
    this.startMarker?.remove();
    this.endMarker?.remove();
    // Route auf der Karte löschen
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
