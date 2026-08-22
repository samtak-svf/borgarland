// A D1-shaped facade over node:sqlite's real SQLite. The relay's tests run the
// actual migration and the actual SQL this way — no in-memory fake of the
// query layer — while the outbound city fetch is stubbed separately.
//
// Only the D1 surface the relay uses is implemented: prepare().bind().all() /
// .run().

import { DatabaseSync } from 'node:sqlite'

export class FakeD1 {
  constructor(readonly sqlite: DatabaseSync) {}

  prepare(sql: string): FakeStatement {
    return new FakeStatement(this.sqlite, sql)
  }
}

class FakeStatement {
  private params: unknown[] = []

  constructor(
    private readonly sqlite: DatabaseSync,
    private readonly sql: string,
  ) {}

  bind(...params: unknown[]): this {
    this.params = params
    return this
  }

  all(): { success: boolean; results: Record<string, unknown>[] } {
    const rows = this.sqlite.prepare(this.sql).all(...this.params)
    return { success: true, results: rows }
  }

  run(): { success: boolean; meta: { changes: number; last_row_id: number } } {
    const info = this.sqlite.prepare(this.sql).run(...this.params)
    return {
      success: true,
      meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) },
    }
  }

  first(): Record<string, unknown> | null {
    const rows = this.sqlite.prepare(this.sql).all(...this.params)
    return rows[0] ?? null
  }
}
