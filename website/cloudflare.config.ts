import { defineConfig } from 'cf/config'

// agentbol.com: the landing page plus /latest.json (the update feed Bol polls) and /download.
// Static assets only (public/); headers and the download redirect live in public/_headers and public/_redirects.
export default defineConfig({
	worker: {
		name: 'agentbol',
		compatibilityDate: '2026-11-25',
		domains: ['agentbol.com', 'www.agentbol.com'],
		// Unknown paths get public/404.html with a 404 status. www.agentbol.com is 301-redirected to the apex by a
		// zone redirect rule, so the page is only ever served at agentbol.com.
		assets: { notFoundHandling: '404-page' },
	},
})
