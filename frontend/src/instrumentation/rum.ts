import type { ApmBase } from '@elastic/apm-rum';

let apm: ApmBase | null = null;

export function getApm(): ApmBase | null {
  if (typeof window === 'undefined') return null;

  if (!apm) {
    const serverUrl = process.env.NEXT_PUBLIC_ELASTIC_APM_SERVER_URL;
    const serviceName = process.env.NEXT_PUBLIC_ELASTIC_APM_SERVICE_NAME || 'demo-frontend';
    const environment = process.env.NEXT_PUBLIC_ELASTIC_APM_ENVIRONMENT || 'local';

    if (!serverUrl) {
      console.warn('[RUM] NEXT_PUBLIC_ELASTIC_APM_SERVER_URL not set — skipping RUM init');
      return null;
    }

    const { init } = require('@elastic/apm-rum');
    apm = init({
      serviceName,
      serverUrl,
      environment,
      distributedTracingOrigins: [process.env.NEXT_PUBLIC_GATEWAY_URL || 'http://localhost:4000'],
    });
  }

  return apm;
}
