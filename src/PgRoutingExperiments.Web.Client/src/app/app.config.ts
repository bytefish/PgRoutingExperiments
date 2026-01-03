import { APP_INITIALIZER, ApplicationConfig } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { AppSettingsService } from './services/app-settings.service';

export function initializeApp(appSettingsService: AppSettingsService) {
  return () => appSettingsService.loadAppSettings();
}

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(),
    {
      provide: APP_INITIALIZER,
      useFactory: initializeApp,
      deps: [AppSettingsService],
      multi: true
    }
  ]
};