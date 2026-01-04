import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { AppSettingsService } from './app-settings.service';

@Injectable({
  providedIn: 'root'
})
export class DebugService {
  private readonly http = inject(HttpClient);

  private readonly settings = inject(AppSettingsService).getAppSettings();

  getRoutingIslands(bounds?: maplibregl.LngLatBounds): Observable<any[]> {
    let params = new HttpParams();

    if (bounds) {
      params = params
        .set('minLon', bounds.getWest().toString())
        .set('minLat', bounds.getSouth().toString())
        .set('maxLon', bounds.getEast().toString())
        .set('maxLat', bounds.getNorth().toString());
    }

    return this.http.get<any[]>(`${this.settings.apiUrl}/debug/islands`, { params });
  }
}
