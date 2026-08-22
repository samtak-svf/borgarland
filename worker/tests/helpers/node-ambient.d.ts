// Minimal ambient declarations for the two Node builtins the tests use. This
// project compiles against @cloudflare/workers-types only (see tsconfig.json),
// so @types/node is deliberately not pulled in — that avoids its globals
// colliding with workers-types' — and these two modules are declared here with
// exactly the surface the tests touch.

declare module 'node:sqlite' {
  export class DatabaseSync {
    constructor(path: string)
    exec(sql: string): void
    prepare(sql: string): PreparedStatement
  }
  export interface PreparedStatement {
    all(...params: unknown[]): Record<string, unknown>[]
    run(...params: unknown[]): { changes: number | bigint; lastInsertRowid: number | bigint }
  }
}

declare module 'node:fs' {
  export function readFileSync(path: string | URL, encoding: string): string
  export function readdirSync(path: string | URL): string[]
}
