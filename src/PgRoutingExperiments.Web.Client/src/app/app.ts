// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MapComponent } from './components/map.component';
import { MapService } from './services/map.service';
import { RoutingService } from './services/routing.service';
import { AppSettingsService } from './services/app-settings.service';
import { debounceTime, distinctUntilChanged, of, Subject, switchMap } from 'rxjs';
import { SearchService } from './services/search.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, MapComponent],
  template: `
    <div class="sidebar">
      <h3>PgRoutingExperiments</h3>

      <div class="search-box">
        <input type="text"
              placeholder="Search address (e.g. Breul 43)..."
              (input)="onSearchInput($event)">

        @if (searchResults().length > 0) {
          <ul class="autocomplete-results">
            @for (res of searchResults(); track res) {
              <li (click)="selectAddress(res)">
                <span class="street">{{ res.street }} {{ res.housenumber }}</span>
                <span class="city">{{ res.plz }} {{ res.city }}</span>
              </li>
            }
          </ul>
        }
      </div>

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

      <div class="debug-controls">
        <label class="checkbox-label">
        <input type="checkbox"
           [checked]="showBBox()"
           (change)="onToggleBBox($event)">
        Show Search Area (BBox)
      </label>
     </div>

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

    .debug-controls {
      margin-top: 15px;
      padding-top: 15px;
      border-top: 1px solid #eee;
    }

    .checkbox-label {
      display: flex;
      align-items: center;
      font-size: 0.85em;
      color: #555;
      cursor: pointer;
    }

.checkbox-label input {
  margin-right: 8px;
  cursor: pointer;
}

.search-box { position: relative; margin-bottom: 15px; }
.search-box input { width: 100%; padding: 10px; border-radius: 4px; border: 1px solid #ccc; }

.autocomplete-results {
  position: absolute;
  top: 100%; left: 0; right: 0;
  background: white;
  border: 1px solid #ccc;
  border-top: none;
  z-index: 100;
  max-height: 300px;
  overflow-y: auto;
  list-style: none;
  padding: 0; margin: 0;
  box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

.autocomplete-results li {
  padding: 10px;
  cursor: pointer;
  border-bottom: 1px solid #eee;
  display: flex;
  flex-direction: column;
}

.autocomplete-results li:hover { background: #f0f7ff; }
.autocomplete-results .street { font-weight: bold; font-size: 0.9em; }
.autocomplete-results .city { font-size: 0.8em; color: #666; }

    .hint { font-size: 0.85em; color: #666; font-style: italic; margin-bottom: 15px; }
  `]
})
export class App {
  // Services
  protected readonly map = inject(MapService);

  private readonly routingService = inject(RoutingService);
  private readonly searchService = inject(SearchService);

  // Get settings
  protected readonly settings = inject(AppSettingsService).getAppSettings();

  readonly transportModes = [
    { id: 'bike', label: 'Bicycle' },
    { id: 'car', label: 'Car' },
    { id: 'walk', label: 'Pedestrian' }
  ];

  // Signals
  readonly selectedMode = signal<string>('bike');

  readonly lastTravelTime = signal<string | null>(null);

  readonly initialCenter = signal<[number, number]>([
    this.settings.mapOptions.mapInitialPoint.lng,
    this.settings.mapOptions.mapInitialPoint.lat
  ]);

  readonly showBBox = signal<boolean>(false);

  readonly initialZoom = signal<number>(this.settings.mapOptions.mapInitialZoom);

  readonly styleUrl = signal<string>(this.settings.mapOptions.mapStyleUrl);

  readonly searchQuery = signal<string>('');
  readonly searchResults = signal<any[]>([]);
  private searchSubject = new Subject<string>();

constructor() {
  // Setup der reaktiven Suche
  this.searchSubject.pipe(
    debounceTime(300), // Warte 300ms
    distinctUntilChanged(), // Nur wenn Text sich geändert hat
    switchMap(term => {
      if (term.length < 3) return of([]); // Erst ab 3 Zeichen suchen
      const center = this.map.getCenter(); // Optional: Aktuelle Kartenmitte für Proximity
      return this.searchService.search(term, center?.lat, center?.lng);
    })
  ).subscribe(results => this.searchResults.set(results));
}

onSearchInput(event: Event) {
  const value = (event.target as HTMLInputElement).value;
  this.searchSubject.next(value);
}

selectAddress(address: any) {
  this.searchResults.set([]); // Liste schließen

  const coords: [number, number] = [address.lon, address.lat];
  this.map.setManualPoint(coords); // Neue Methode im MapService
}

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
      this.routingService.getRoute(this.selectedMode(), start, end).subscribe({
        next: (geojson: any) => {
          this.map.setRoute(geojson);

          if (geojson.debugBBox) {
            this.map.showDebugBBox(geojson.debugBBox);
          }

          this.formatTravelTime(geojson);
        },
        error: (err: any) => alert('Routing error: ' + err.message)
      });
    }
  }

  onToggleBBox(event: Event) {
    const checkbox = event.target as HTMLInputElement;
    this.showBBox.set(checkbox.checked);

    this.map.toggleBBoxVisibility(this.showBBox());
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
