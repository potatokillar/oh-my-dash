/**
 * dsh-remote-access: the remoteAccess service row.
 *
 * Holds the deployment's extra trusted authorities for the /api browser-trust
 * fence. The bundle patch concatenates them onto the connection row's
 * trustedHosts; users override the whole config in their profile patch:
 *
 *   - id: remote-access
 *     config:
 *       hosts: ['phone.example.com', 'nas.lan:3080']
 *
 * Each entry must be a bare, canonical `host[:port]` authority — the
 * connection plugin fail-loads on anything WHATWG parsing rewrites.
 */

export const name = 'remote-access';

/** @param ctx - Cordis context. @param config - row config. */
export function apply(ctx, config) {
  ctx.provide('remoteAccess', { hosts: config?.hosts ?? [] });
}
