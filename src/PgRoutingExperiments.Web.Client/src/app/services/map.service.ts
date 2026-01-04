// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Injectable, signal, NgZone, inject } from '@angular/core';
import * as maplibregl from 'maplibre-gl';
import { Subject } from 'rxjs';

@Injectable({
  providedIn: 'root',
})
export class MapService {
  private readonly zone = inject(NgZone);
  private map?: maplibregl.Map;

  private mapMoveSubject = new Subject<void>();
  mapMove$ = this.mapMoveSubject.asObservable();

  readonly isLoaded = signal(false);
  readonly startPoint = signal<[number, number] | null>(null);
  readonly endPoint = signal<[number, number] | null>(null);
  readonly activeInput = signal<'start' | 'end'>('start');

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

      this.map.on('moveend', () => this.mapMoveSubject.next());

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

  getMapBounds(): maplibregl.LngLatBounds | undefined {
    if (!this.map)
      return undefined;

    return this.map.getBounds();
  }

  showIslandDebug(islands: any[]) {
    // Wir definieren das Objekt explizit als FeatureCollection
    const geojson: any = {
      type: 'FeatureCollection',
      features: islands.map(i => ({
        type: 'Feature',
        geometry: typeof i.geometry === 'string' ? JSON.parse(i.geometry) : i.geometry,
        properties: {
          component: i.component_id,
          id: i.id
        }
      }))
    };

    const source = this.map?.getSource('islands') as maplibregl.GeoJSONSource;

    if (source) {
      source.setData(geojson);
    } else {
      this.map?.addSource('islands', {
        type: 'geojson',
        data: geojson // Jetzt passt der Typ
      });

      this.map?.addLayer({
        id: 'islands-layer',
        type: 'line',
        source: 'islands',
        paint: {
          'line-color': '#ff4d4d',
          'line-width': 2.5,
          'line-dasharray': [2, 1]
        }
      });
    }
  }

  removeIslandDebug(): void {
    if (!this.map)
      return;

    if (this.map.getLayer('islands-layer')) {
      this.map.removeLayer('islands-layer');
    }

    // Dann die Datenquelle (Source) entfernen
    if (this.map.getSource('islands')) {
      this.map.removeSource('islands');
    }
  }

  setManualPoint(coords: [number, number], type?: 'start' | 'end'): void {
    const targetType = type ?? this.activeInput();
    const lngLat = new maplibregl.LngLat(coords[0], coords[1]);

  if (targetType === 'start') {
    this.startPoint.set(coords);
    if (!this.startMarker) {
      this.startMarker = this.createDraggableMarker('#2ecc71', 'start');
    }
    this.startMarker.setLngLat(lngLat).addTo(this.map!);
    // Auto-switch focus to end if start was just set
    this.activeInput.set('end');
    } else {
      this.endPoint.set(coords);
      if (!this.endMarker) {
        this.endMarker = this.createDraggableMarker('#e74c3c', 'end');
      }
      this.endMarker.setLngLat(lngLat).addTo(this.map!);
    }
}

  private createDraggableMarker(color: string, type: 'start' | 'end') {
    const marker = new maplibregl.Marker({ color, draggable: true });

    marker.on('dragend', () => {
      const pos = marker.getLngLat();
      this.zone.run(() => {
        if (type === 'start') this.startPoint.set([pos.lng, pos.lat]);
        else this.endPoint.set([pos.lng, pos.lat]);
      });
    });

    return marker;
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
