// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import { HttpClient, HttpParams } from "@angular/common/http";
import { inject, Injectable } from "@angular/core";
import { AppSettingsService } from "./app-settings.service";
import { Observable } from "rxjs";

@Injectable({ providedIn: 'root' })
export class RoutingService {
  private readonly http = inject(HttpClient);
  private readonly settings = inject(AppSettingsService).getAppSettings();

  getRoute(mode: string, start: [number, number], end: [number, number]): Observable<any> {
    // Uses the URL from appsettings.json
    const url = `${this.settings.apiUrl}/route`;

    const params = new HttpParams()
      .set('mode', mode)
      .set('startLon', start[0].toString())
      .set('startLat', start[1].toString())
      .set('endLon', end[0].toString())
      .set('endLat', end[1].toString());

    return this.http.get<any>(url, { params });
  }
}
