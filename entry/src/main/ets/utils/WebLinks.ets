import { isInAppBrowserUrl } from './SafeUrl';

/** Canonical Cursor Web surfaces for features the native API cannot cover fully. */
export class WebLinks {
  static readonly agentsHome: string = 'https://cursor.com/agents';
  static readonly integrations: string = 'https://cursor.com/dashboard/integrations';
  static readonly cloudAgentsSettings: string = 'https://cursor.com/dashboard/cloud-agents';
  static readonly apiKeys: string = 'https://cursor.com/dashboard/api';
  static readonly docsCloud: string = 'https://cursor.com/docs/cloud-agent';
  static readonly docsSetup: string = 'https://cursor.com/docs/cloud-agent/setup';
  static readonly docsMcp: string = 'https://cursor.com/docs/cloud-agent/capabilities';
  static readonly docsApi: string = 'https://cursor.com/docs/cloud-agent/api/endpoints';
  static readonly docsApiOverview: string = 'https://cursor.com/docs/api';

  static agentPage(agentIdOrUrl: string): string {
    if (!agentIdOrUrl) {
      return WebLinks.agentsHome;
    }
    if (agentIdOrUrl.indexOf('https://') === 0 || agentIdOrUrl.indexOf('http://') === 0) {
      return agentIdOrUrl;
    }
    return `https://cursor.com/agents/${agentIdOrUrl}`;
  }
}

/** Push InAppBrowser onto the shared NavPathStack. */
export function pushInAppBrowser(nav: NavPathStack, url: string, title: string = 'Web'): void {
  if (!url || url.length === 0 || !isInAppBrowserUrl(url)) {
    return;
  }
  const param: Record<string, Object> = {};
  param['url'] = url;
  param['title'] = title;
  nav.pushPath({ name: 'InAppBrowser', param: param });
}
