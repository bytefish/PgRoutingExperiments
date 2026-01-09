// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { AppSettingsService } from './app-settings.service';

@Injectable({ providedIn: 'root' })
export class GeocodingService {
  private readonly http = inject(HttpClient);
  private readonly settings = inject(AppSettingsService).getAppSettings();

  geocode(query: string, lat?: number, lon?: number): Observable<any[]> {
    let params = new HttpParams().set('query', query);
    if (lat && lon) {
      params = params.set('refLat', lat).set('refLon', lon);
    }
    return this.http.get<any[]>(`${this.settings.apiUrl}/geocode`, { params });
  }

  reverseGeocode(lat: number, lon: number): Observable<any> {
    const params = new HttpParams().set('lat', lat.toString()).set('lon', lon.toString());

    return this.http.get<any>(`${this.settings.apiUrl}/reverse-geocode`, { params });
  }
}
