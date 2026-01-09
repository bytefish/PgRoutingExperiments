import { ApplicationConfig, inject, provideAppInitializer } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { AppSettingsService } from './services/app-settings.service';

export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(),
    provideAppInitializer(() => {
      const settingsService = inject(AppSettingsService);
      return settingsService.loadAppSettings();
    }),
  ],
};
