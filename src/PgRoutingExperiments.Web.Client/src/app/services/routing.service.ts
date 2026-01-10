// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { HttpClient } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { AppSettingsService } from './app-settings.service';
import { Observable } from 'rxjs';
import { RouteOptions, TransportMode } from '../model/routing';

@Injectable({ providedIn: 'root' })
export class RoutingService {
  private readonly http = inject(HttpClient);
  private readonly settings = inject(AppSettingsService).getAppSettings();

  getRoute(
    mode: TransportMode,
    start: [number, number],
    end: [number, number],
    useTrsp: boolean,
    options: RouteOptions
  ): Observable<any> {
    const url = `${this.settings.apiUrl}/route`;

    const body = {
      startLon: start[0],
      startLat: start[1],
      endLon: end[0],
      endLat: end[1],
      mode: mode,
      useTrsp: useTrsp,
      options: options,
    };

    return this.http.post<any>(url, body);
  }
}
