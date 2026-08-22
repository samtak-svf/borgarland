// Worker entry. The app itself lives in app.ts, which is what the tests drive;
// this file only wires the production environment into it.
//
// The registry is loaded lazily on the first request that needs it and cached
// per isolate (see registry-loader.ts).

import { createApp } from './app'
import type { Env } from './env'
import { loadRegistry } from './registry-loader'

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const app = createApp(env, {
      fetch: globalThis.fetch,
      getRegistry: () => loadRegistry(env.DB),
    })
    return app(request)
  },
}
