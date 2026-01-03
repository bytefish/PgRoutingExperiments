// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MapComponent } from './components/map.component';
import { MapService } from './services/map.service';
import { RoutingService } from './services/routing.service';
import { AppSettingsService } from './services/app-settings.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, MapComponent],
  template: `
    <div class="sidebar">
      <h3>PgRoutingExperiments</h3>

      <div class="mode-selector">
        <label>Transport Mode:</label>
        <select [value]="selectedMode()" (change)="onModeChange($event)">
          @for (mode of transportModes; track mode.id) {
            <option [value]="mode.id">{{ mode.label }}</option>
          }
        </select>
      </div>

      <hr />

      <p class="hint">Click on the map to select start and destination.</p>

      <div class="points-status">
        <div [class.active]="map.startPoint()">
          Start Point: {{ map.startPoint() ? 'Set ✓' : 'Not selected' }}
        </div>
        <div [class.active]="map.endPoint()">
          Destination: {{ map.endPoint() ? 'Set ✓' : 'Not selected' }}
        </div>
      </div>

      <button class="primary-btn"
              [disabled]="!map.startPoint() || !map.endPoint()"
              (click)="calculateRoute()">
        Calculate Route
      </button>

      <button class="secondary-btn" (click)="map.resetRouting()">
        Reset Map
      </button>

      @if (lastTravelTime()) {
        <div class="result-info">
          <strong>Estimated Time:</strong> {{ lastTravelTime() }}
        </div>
      }
    </div>

    <maplibre-map
      class="map-container"
      [mapStyle]="settings.mapOptions.mapStyleUrl"
      [center]="[settings.mapOptions.mapInitialPoint.lng, settings.mapOptions.mapInitialPoint.lat]"
      [zoom]="settings.mapOptions.mapInitialZoom">
    </maplibre-map>
  `,
  styles: [`
    :host { display: block; height: 100vh; width: 100vw; overflow: hidden; }
    .map-container { height: 100%; width: 100%; }

    .sidebar {
      position: absolute; z-index: 10; background: white;
      padding: 20px; margin: 10px; border-radius: 8px;
      box-shadow: 0 4px 15px rgba(0,0,0,0.15); width: 260px;
    }

    .mode-selector { margin-bottom: 15px; }
    .mode-selector label { display: block; margin-bottom: 5px; font-weight: bold; font-size: 0.9em; }
    select { width: 100%; padding: 8px; border-radius: 4px; border: 1px solid #ccc; }

    .points-status { font-size: 0.9em; margin-bottom: 15px; }
    .points-status div { color: #888; margin-bottom: 5px; transition: color 0.3s ease; }
    .points-status div.active { color: #2ecc71; font-weight: bold; }

    .primary-btn {
      width: 100%; background: #007cbf; color: white; border: none;
      padding: 12px; border-radius: 4px; cursor: pointer; font-weight: bold;
    }
    .primary-btn:disabled { background: #ccc; cursor: not-allowed; }

    .secondary-btn {
      width: 100%; background: transparent; color: #666; border: 1px solid #ccc;
      padding: 8px; border-radius: 4px; cursor: pointer; margin-top: 8px;
    }

    .result-info {
      margin-top: 20px; padding: 12px; background: #f0f7ff;
      border-radius: 4px; border-left: 4px solid #007cbf;
    }

    .hint { font-size: 0.85em; color: #666; font-style: italic; margin-bottom: 15px; }
  `]
})
export class App {
  // Services
  protected readonly map = inject(MapService);
  private readonly routing = inject(RoutingService);

  // Get settings
  protected readonly settings = inject(AppSettingsService).getAppSettings();

  readonly transportModes = [
    { id: 'bike', label: 'Bicycle' },
    { id: 'car', label: 'Car' },
    { id: 'walk', label: 'Pedestrian' }
  ];

  readonly selectedMode = signal<string>('bike');

  readonly lastTravelTime = signal<string | null>(null);

  readonly initialCenter = signal<[number, number]>([
    this.settings.mapOptions.mapInitialPoint.lng,
    this.settings.mapOptions.mapInitialPoint.lat
  ]);

  readonly initialZoom = signal<number>(this.settings.mapOptions.mapInitialZoom);

  readonly styleUrl = signal<string>(this.settings.mapOptions.mapStyleUrl);

  onModeChange(event: Event) {
    const select = event.target as HTMLSelectElement;
    this.selectedMode.set(select.value);
    if (this.map.startPoint() && this.map.endPoint()) {
      this.calculateRoute();
    }
  }

  calculateRoute() {
    const start = this.map.startPoint();
    const end = this.map.endPoint();

    if (start && end) {
      this.routing.getRoute(this.selectedMode(), start, end).subscribe({
        next: (geojson: any) => {
          this.map.setRoute(geojson);
          this.formatTravelTime(geojson);
        },
        error: (err: any) => alert('Routing error: ' + err.message)
      });
    }
  }

  private formatTravelTime(geojson: any) {
    const totalSeconds = geojson.features.reduce(
      (acc: number, f: any) => acc + (f.properties.seconds || 0), 0
    );

    if (totalSeconds > 0) {
      const minutes = Math.floor(totalSeconds / 60);
      const remainingSeconds = Math.round(totalSeconds % 60);
      this.lastTravelTime.set(minutes > 0 ? `${minutes} min ${remainingSeconds} sec` : `${remainingSeconds} sec`);
    } else {
      this.lastTravelTime.set(null);
    }
  }
}
