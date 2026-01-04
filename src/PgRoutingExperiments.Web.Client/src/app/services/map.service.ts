// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Injectable, signal, NgZone, inject } from '@angular/core';
import * as maplibregl from 'maplibre-gl';

@Injectable({
  providedIn: 'root',
})
export class MapService {
  private readonly zone = inject(NgZone);
  private map?: maplibregl.Map;

  // Status-Signale für die UI
  readonly isLoaded = signal(false);
  readonly startPoint = signal<[number, number] | null>(null);
  readonly endPoint = signal<[number, number] | null>(null);

  private startMarker?: maplibregl.Marker;
  private endMarker?: maplibregl.Marker;

  buildMap(container: HTMLElement, style: any, center: any, zoom: any): void {
    this.zone.runOutsideAngular(() => {
      this.map = new maplibregl.Map({
        container,
        style: style || 'https://demotiles.maplibre.org/style.json',
        center: center || [7.628, 51.96],
        zoom: zoom || 12,
        attributionControl: false
      });

      this.map.on('load', () => {
        this.setupLayers();
        this.zone.run(() => this.isLoaded.set(true));
      });

      this.map.on('click', (e) => {
        this.zone.run(() => this.handleMapClick(e.lngLat));
      });
    });
  }

  private setupLayers(): void {
    if (!this.map) return;

    // 1. Route Layer
    this.map.addSource('route', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    });

    this.map.addLayer({
      id: 'route-line',
      type: 'line',
      source: 'route',
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: {
        'line-color': '#007cbf',
        'line-width': 5,
        'line-opacity': 0.8
      }
    });

    // 2. Debug BBox Layer
    this.map.addSource('debug-bbox', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    });

    this.map.addLayer({
      id: 'bbox-layer',
      type: 'fill',
      source: 'debug-bbox',
      layout: { 'visibility': 'none' },
      paint: {
        'fill-color': '#ff0000',
        'fill-opacity': 0.1,
        'fill-outline-color': '#ff0000'
      }
    });
  }

  /**
   * Setzt einen Punkt manuell (z.B. vom Geocoder)
   */
  setManualPoint(coords: [number, number], type: 'start' | 'end' = 'start'): void {
    const lngLat = new maplibregl.LngLat(coords[0], coords[1]);

    if (type === 'start') {
      this.startPoint.set(coords);
      this.startMarker?.remove();
      this.startMarker = new maplibregl.Marker({ color: '#2ecc71' }).setLngLat(lngLat).addTo(this.map!);
    } else {
      this.endPoint.set(coords);
      this.endMarker?.remove();
      this.endMarker = new maplibregl.Marker({ color: '#e74c3c' }).setLngLat(lngLat).addTo(this.map!);
    }

    this.map?.flyTo({ center: lngLat, zoom: 15 });
  }

  private handleMapClick(lngLat: maplibregl.LngLat): void {
    const coords: [number, number] = [lngLat.lng, lngLat.lat];

    if (!this.startPoint()) {
      this.setManualPoint(coords, 'start');
    } else if (!this.endPoint()) {
      this.setManualPoint(coords, 'end');
    } else {
      this.resetRouting();
      this.setManualPoint(coords, 'start');
    }
  }

  setRoute(geojson: any): void {
    const source = this.map?.getSource('route') as maplibregl.GeoJSONSource;
    if (source && geojson.features.length > 0) {
      source.setData(geojson);

      const bounds = new maplibregl.LngLatBounds();
      geojson.features.forEach((f: any) => {
        f.geometry.coordinates.forEach((c: any) => {
          // Prüfen ob verschachtelt (LineString) oder einzeln (Point)
          if (Array.isArray(c[0])) {
            c.forEach((cc: any) => bounds.extend(cc));
          } else {
            bounds.extend(c);
          }
        });
      });
      this.map?.fitBounds(bounds, { padding: 50 });
    }
  }

  showDebugBBox(bbox: any): void {
    const source = this.map?.getSource('debug-bbox') as maplibregl.GeoJSONSource;
    if (!source) return;

    const polygon = {
      type: 'Feature',
      geometry: {
        type: 'Polygon',
        coordinates: [[
          [bbox.minLon, bbox.minLat],
          [bbox.maxLon, bbox.minLat],
          [bbox.maxLon, bbox.maxLat],
          [bbox.minLon, bbox.maxLat],
          [bbox.minLon, bbox.minLat]
        ]]
      }
    };
    source.setData({ type: 'FeatureCollection', features: [polygon as any] });
  }

  toggleBBoxVisibility(visible: boolean): void {
    if (this.map?.getLayer('bbox-layer')) {
      this.map.setLayoutProperty('bbox-layer', 'visibility', visible ? 'visible' : 'none');
    }
  }

  getCenter(): maplibregl.LngLat | undefined {
    return this.map?.getCenter();
  }

  resetRouting(): void {
    this.startPoint.set(null);
    this.endPoint.set(null);
    this.startMarker?.remove();
    this.endMarker?.remove();
    (this.map?.getSource('route') as maplibregl.GeoJSONSource)?.setData({ type: 'FeatureCollection', features: [] });
    (this.map?.getSource('debug-bbox') as maplibregl.GeoJSONSource)?.setData({ type: 'FeatureCollection', features: [] });
  }

  destroyMap(): void {
    this.map?.remove();
  }
}
