// Licensed under the MIT license. See LICENSE file in the project root for full license information.

import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  OnDestroy,
  input,
  viewChild,
  inject,
} from '@angular/core';
import { MapService } from '../services/map.service';
import { StyleSpecification, LngLatLike } from 'maplibre-gl';

@Component({
  selector: 'maplibre-map',
  standalone: true,
  template: '<div #container></div>',
  styles: `
    :host {
      display: block;
      height: 100%;
      width: 100%;
    }

    div {
      height: 100%;
      width: 100%;
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class MapComponent implements AfterViewInit, OnDestroy {
  private readonly mapService = inject(MapService);

  private readonly mapContainer = viewChild.required<ElementRef<HTMLDivElement>>('container');

  readonly mapStyle = input<StyleSpecification | string>(
    'https://demotiles.maplibre.org/style.json'
  );

  readonly center = input<LngLatLike>([7.628, 51.96]);
  readonly zoom = input<number>(12);

  ngAfterViewInit(): void {
    const containerElement = this.mapContainer().nativeElement;

    this.mapService.buildMap(containerElement, this.mapStyle(), this.center(), this.zoom());
  }

  ngOnDestroy(): void {
    this.mapService.destroyMap();
  }
}
