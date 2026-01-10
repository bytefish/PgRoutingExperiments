// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { Component, inject, signal, OnInit, effect, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MapComponent } from './components/map.component';
import { MapService } from './services/map.service';
import { RoutingService } from './services/routing.service';
import { AppSettingsService } from './services/app-settings.service';
import {
  catchError,
  debounceTime,
  distinctUntilChanged,
  filter,
  of,
  Subject,
  switchMap,
} from 'rxjs';
import { GeocodingService } from './services/geocoding.service';
import { DebugService } from './services/debug.service';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouteOptions, TransportMode, TransportModeOption } from './model/routing';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, MapComponent],
  template: `
    <div class="sidebar">
      <div class="mode-selector">
        <button [class.active]="selectedMode() === 'car'" (click)="selectedMode.set('car')">
          🚗
        </button>
        <button [class.active]="selectedMode() === 'bike'" (click)="selectedMode.set('bike')">
          🚲
        </button>
        <button [class.active]="selectedMode() === 'foot'" (click)="selectedMode.set('foot')">
          🚶
        </button>
      </div>

      <div class="routing-container">
        <div class="input-wrapper" [class.is-active]="mapService.activeInput() === 'start'">
          <div class="dot start"></div>
          <input
            type="text"
            [value]="startSearchQuery()"
            (focus)="mapService.activeInput.set('start')"
            (input)="onInput($event, 'start')"
            placeholder="Choose start point..."
          />

          @if (startResults().length > 0) {
          <ul class="autocomplete-list">
            @for (res of startResults(); track res) {
            <li (click)="selectLocation(res, 'start')">
              <strong>{{ res.street }} {{ res.housenumber }}</strong>
              <small>{{ res.plz }} {{ res.city }}</small>
            </li>
            }
          </ul>
          }
        </div>

        <button class="swap-btn" (click)="swapPoints()" title="Swap start and destination">
          ⇅
        </button>

        <div class="input-wrapper" [class.is-active]="mapService.activeInput() === 'end'">
          <div class="dot end"></div>
          <input
            type="text"
            [value]="endSearchQuery()"
            (focus)="mapService.activeInput.set('end')"
            (input)="onInput($event, 'end')"
            placeholder="Choose destination..."
          />

          @if (endResults().length > 0) {
          <ul class="autocomplete-list">
            @for (res of endResults(); track res) {
            <li (click)="selectLocation(res, 'end')">
              <strong>{{ res.street }} {{ res.housenumber }}</strong>
              <small>{{ res.plz }} {{ res.city }}</small>
            </li>
            }
          </ul>
          }
        </div>
      </div>

      <div class="results-panel">
        @if (travelTime()) {
        <div class="time-display">
          <span class="label">Estimated Travel Time</span>
          <span class="value">{{ travelTime() }}</span>
        </div>
        }

        <button
          class="primary-btn"
          [disabled]="!mapService.startPoint() || !mapService.endPoint()"
          (click)="triggerRoute()"
        >
          Get Directions
        </button>

        <button class="clear-btn" (click)="resetAll()">Clear Route</button>
      </div>

      <div class="debug-footer">
        <label class="checkbox-container">
          <input
            type="checkbox"
            [checked]="useTrsp()"
            (change)="toggleUseTrsp($event)"
          />
          <span>Use TRSP Algorithm</span>
        </label>

        <label class="checkbox-container">
          <input
            type="checkbox"
            [checked]="options().exclude_motorway"
            (change)="toggleOption('exclude_motorway')"
          />
          <span>Exclude Motorways</span>
        </label>

        <label class="checkbox-container">
          <input
            type="checkbox"
            [checked]="options().avoid_motorway"
            (change)="toggleOption('avoid_motorway')"
          />
          <span>Avoid Motorways</span>
        </label>

        @if (selectedMode() === 'car') {
        <label class="checkbox-container">
          <input
            type="checkbox"
            [checked]="options().optimize_consumption"
            (change)="toggleOption('optimize_consumption')"
          />
          <span>Optimize Consumption</span>
        </label>
        }

        <label class="checkbox-container">
          <input type="checkbox" [checked]="showIslands()" (change)="toggleIslands($event)" />
          <span style="color: red;">⚠ Show Routing Islands</span>
        </label>
      </div>
    </div>
    <maplibre-map
      class="map-container"
      [mapStyle]="settings.mapOptions.mapStyleUrl"
      [center]="[settings.mapOptions.mapInitialPoint.lng, settings.mapOptions.mapInitialPoint.lat]"
      [zoom]="settings.mapOptions.mapInitialZoom"
    >
    </maplibre-map>
  `,
  styles: [
    `
      :host {
        display: block;
        height: 100vh;
        width: 100vw;
        overflow: hidden;
      }

      .map-container {
        height: 100%;
        width: 100%;
      }

      /* Sidebar Container */
      .sidebar {
        position: absolute;
        top: 10px;
        left: 10px;
        width: 350px;
        max-height: calc(100vh - 40px);
        background: white;
        padding: 20px;
        border-radius: 12px;
        box-shadow: 0 4px 25px rgba(0, 0, 0, 0.15);
        z-index: 10;
        display: flex;
        flex-direction: column;
        font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      }

      /* 1. Mode Selector */
      .mode-selector {
        display: flex;
        background: #f0f0f0;
        padding: 4px;
        border-radius: 10px;
        margin-bottom: 20px;
      }

      .mode-selector button {
        flex: 1;
        border: none;
        background: transparent;
        padding: 10px;
        cursor: pointer;
        font-size: 1.2rem;
        border-radius: 8px;
        transition: all 0.2s ease;
      }

      .mode-selector button.active {
        background: white;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
      }

      .mode-selector button:hover:not(.active) {
        background: rgba(255, 255, 255, 0.5);
      }

      .routing-container {
        display: flex;
        flex-direction: column;
        position: relative;
      }

      .input-wrapper {
        display: flex;
        align-items: center;
        background: #f8f9fa;
        border: 2px solid #f8f9fa;
        border-radius: 8px;
        padding: 8px 12px;
        transition: all 0.2s ease;
        position: relative;
      }

      .input-wrapper.is-active {
        background: white;
        border-color: #007cbf;
        box-shadow: 0 0 0 4px rgba(0, 124, 191, 0.1);
      }

      .input-wrapper input {
        flex: 1;
        border: none;
        background: transparent;
        font-size: 0.95rem;
        padding: 4px 0;
        color: #333;
        outline: none;
      }

      .dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        margin-right: 12px;
        flex-shrink: 0;
      }

      .dot.start {
        background: #2ecc71;
        border: 2px solid #27ae60;
      }
      .dot.end {
        background: #e74c3c;
        border: 2px solid #c0392b;
      }

      .connector-line {
        width: 2px;
        height: 20px;
        background: #ddd;
        margin-left: 16px;
      }

      /* Swap Button */
      .swap-btn {
        position: absolute;
        right: -5px;
        top: 50%;
        transform: translateY(-50%);
        background: white;
        border: 1px solid #ddd;
        border-radius: 50%;
        width: 28px;
        height: 28px;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 1rem;
        color: #666;
        z-index: 2;
        transition: background 0.2s;
      }

      .swap-btn:hover {
        background: #f0f0f0;
        color: #333;
      }

      .autocomplete-list {
        position: absolute;
        top: 100%;
        left: 0;
        right: 0;
        background: white;
        border-radius: 8px;
        margin-top: 5px;
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.1);
        max-height: 200px;
        overflow-y: auto;
        list-style: none;
        padding: 0;
        z-index: 100;
      }

      .autocomplete-list li {
        padding: 10px 15px;
        cursor: pointer;
        border-bottom: 1px solid #f0f0f0;
      }

      .autocomplete-list li:hover {
        background: #f8faff;
      }

      .autocomplete-list li strong {
        display: block;
        font-size: 0.9rem;
        color: #333;
      }

      .autocomplete-list li small {
        font-size: 0.8rem;
        color: #888;
      }

      .results-panel {
        margin-top: 20px;
      }

      .time-display {
        background: #eef8ff;
        border: 1px solid #d0e6f5;
        border-radius: 10px;
        padding: 15px;
        text-align: center;
        margin-bottom: 20px;
      }

      .time-display .label {
        display: block;
        font-size: 0.8rem;
        color: #5a7b92;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }

      .time-display .value {
        font-size: 1.6rem;
        font-weight: 700;
        color: #007cbf;
      }

      .primary-btn {
        width: 100%;
        padding: 14px;
        background: #007cbf;
        color: white;
        border: none;
        border-radius: 8px;
        font-size: 1rem;
        font-weight: 600;
        cursor: pointer;
        transition: background 0.2s;
      }

      .primary-btn:hover {
        background: #00669d;
      }
      .primary-btn:disabled {
        background: #ccc;
        cursor: not-allowed;
      }

      .clear-btn {
        width: 100%;
        background: none;
        border: none;
        color: #888;
        padding: 10px;
        cursor: pointer;
        font-size: 0.9rem;
        text-decoration: underline;
      }

      /* 5. Debug Footer */
      .debug-footer {
        margin-top: 20px;
        padding-top: 15px;
        border-top: 1px solid #eee;
      }

      .checkbox-container {
        display: flex;
        align-items: center;
        font-size: 0.85rem;
        color: #666;
        cursor: pointer;
        user-select: none;
      }

      .checkbox-container input {
        margin-right: 10px;
      }
    `,
  ],
})
export class App {
  // Application Settings
  protected readonly settings = inject(AppSettingsService).getAppSettings();

  // Services
  protected readonly mapService = inject(MapService);
  protected readonly debugService = inject(DebugService);
  protected readonly routingService = inject(RoutingService);
  protected readonly geocodeService = inject(GeocodingService);

  // Signals for the Transportation Mode
  readonly selectedMode = signal<TransportMode>('bike');

  readonly travelTime = signal<string | null>(null);

  readonly useTrsp = signal<boolean>(false);

  // Signals for the Map
  readonly initialCenter = signal<[number, number]>([
    this.settings.mapOptions.mapInitialPoint.lng,
    this.settings.mapOptions.mapInitialPoint.lat,
  ]);

  readonly initialZoom = signal<number>(this.settings.mapOptions.mapInitialZoom);

  readonly styleUrl = signal<string>(this.settings.mapOptions.mapStyleUrl);

  readonly showIslands = signal<boolean>(false);

  // Signals for Searching the Start Point
  readonly startSearchQuery = signal<string>('');
  readonly startResults = signal<any[]>([]);
  private startSearchSubject = new Subject<string>();

  // Signals for Searching the End Point
  readonly endSearchQuery = signal<string>('');
  readonly endResults = signal<any[]>([]);
  private endSearchSubject = new Subject<string>();

  /**
   * Options for the calculating a route.
   */
  options = signal<RouteOptions>({
    avoid_motorway: false,
    exclude_motorway: false,
    avoid_ferry: false,
    optimize_consumption: false,
  });

  constructor() {
    effect(
      () => {
        const start = this.mapService.startPoint();

        if (start) {
          this.updateAddress(start, 'start');
        }
      },
      { allowSignalWrites: true }
    );

    effect(
      () => {
        const end = this.mapService.endPoint();

        if (end) {
          this.updateAddress(end, 'end');
        }
      },
      { allowSignalWrites: true }
    );

    // We subscribe to the MapMove Event, so we can request the
    // network islands for the current view, instead of loading it
    // for the entire map.
    this.mapService.mapMove$
      .pipe(
        filter(() => this.showIslands()),
        debounceTime(200),
        switchMap(() => {
          const bounds = this.mapService.getMapBounds();

          return this.debugService.getRoutingIslands(bounds);
        }),
        catchError((err) => {
          console.error(err);
          return of([]);
        }),
        takeUntilDestroyed()
      )
      .subscribe((data) => {
        this.mapService.showIslandDebug(data);
      });

    // We subscribe to the start input changes
    this.startSearchSubject
      .pipe(
        debounceTime(300),
        distinctUntilChanged(),
        switchMap((term) => {
          if (term.length < 3) {
            return of([]);
          }

          const center = this.mapService.getCenter();

          return this.geocodeService.geocode(term, center?.lat, center?.lng);
        })
      )
      .subscribe((results) => this.startResults.set(results));

    // We subscribe to the end input changes
    this.endSearchSubject
      .pipe(
        debounceTime(300),
        distinctUntilChanged(),
        switchMap((term) => {
          if (term.length < 3) {
            return of([]);
          }

          const center = this.mapService.getCenter();

          return this.geocodeService.geocode(term, center?.lat, center?.lng);
        })
      )
      .subscribe((results) => this.endResults.set(results));
  }

  // Clear everything and reset focus to start
  resetAll() {
    this.mapService.resetRouting();
    this.startSearchQuery.set('');
    this.endSearchQuery.set('');
    this.mapService.activeInput.set('start');
  }

  onInput(event: Event, type: 'start' | 'end') {
    const val = (event.target as HTMLInputElement).value;
    if (type === 'start') {
      this.startSearchQuery.set(val);
      this.startSearchSubject.next(val);
    } else {
      this.endSearchQuery.set(val);
      this.endSearchSubject.next(val);
    }
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: MouseEvent) {
    if (!(event.target as HTMLElement).closest('.input-wrapper')) {
      this.startResults.set([]);
      this.endResults.set([]);
    }
  }

  toggleOption(key: keyof RouteOptions) {
    this.options.update((prev) => ({
      ...prev,
      [key]: !prev[key],
    }));
  }

  toggleUseTrsp(event: Event) {
    const checked = (event.target as HTMLInputElement).checked;
    this.useTrsp.set(checked);
  }

  toggleIslands(event: Event) {
    const checked = (event.target as HTMLInputElement).checked;
    this.showIslands.set(checked);

    if (checked) {
      const bounds = this.mapService.getMapBounds();
      this.debugService
        .getRoutingIslands(bounds)
        .subscribe((data) => this.mapService.showIslandDebug(data));
    } else {
      this.mapService.removeIslandDebug();
    }
  }

  triggerRoute() {
    const start = this.mapService.startPoint();
    const end = this.mapService.endPoint();

    if (start && end) {
      this.routingService
        .getRoute(this.selectedMode(), start, end, this.useTrsp(), this.options())
        .subscribe((response) => {
          this.mapService.setRoute(response);

          // Calculate total seconds from all segments (out_seconds)
          const totalSeconds = response.features.reduce(
            (acc: number, f: any) => acc + (f.properties.seconds || 0),
            0
          );

          this.travelTime.set(this.formatDuration(totalSeconds));
        });
    }
  }

  // Helper to swap Start and End
  swapPoints() {
    const s = this.mapService.startPoint();
    const e = this.mapService.endPoint();
    const sText = this.startSearchQuery();
    const eText = this.endSearchQuery();

    this.mapService.startPoint.set(e);
    this.mapService.endPoint.set(s);
    this.startSearchQuery.set(eText);
    this.endSearchQuery.set(sText);

    // Update markers on map
    if (e) this.mapService.setManualPoint(e, 'start');
    if (s) this.mapService.setManualPoint(s, 'end');
  }

  formatDuration(seconds: number): string {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return `${h} h ${m} min`;
    return `${m} min`;
  }

  selectLocation(address: any, type: 'start' | 'end') {
    const coords: [number, number] = [address.lon, address.lat];
    const label = `${address.street} ${address.housenumber}, ${address.city}`;

    if (type === 'start') {
      this.startSearchQuery.set(label);
      this.startResults.set([]);
      this.mapService.setManualPoint(coords, 'start');
    } else {
      this.endSearchQuery.set(label);
      this.endResults.set([]);
      this.mapService.setManualPoint(coords, 'end');
    }
  }

  onModeChange(event: Event) {
    const select = event.target as HTMLSelectElement;

    if (select.value !== 'car' && select.value !== 'bike' && select.value !== 'foot') {
      return;
    }

    this.selectedMode.set(select.value);

    if (this.mapService.startPoint() && this.mapService.endPoint()) {
      this.triggerRoute();
    }
  }

  private updateAddress(coords: [number, number], type: 'start' | 'end') {
    this.geocodeService.reverseGeocode(coords[1], coords[0]).subscribe((addr) => {
      const streetPart = `${addr.street} ${addr.housenumber || ''}`.trim();
      const cityPart = `${addr.plz || ''} ${addr.city || ''}`.trim();
      const label = cityPart ? `${streetPart}, ${cityPart}` : streetPart;

      if (type === 'start') this.startSearchQuery.set(label);
      else this.endSearchQuery.set(label);
    });
  }
}
