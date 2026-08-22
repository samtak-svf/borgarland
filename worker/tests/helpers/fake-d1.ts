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

  /**
   * D1's batch is a transaction, and the relay relies on that: a client event
   * timeline lands whole or not at all. node:sqlite gives us a real one, so the
   * tests exercise the same all-or-nothing property rather than a loop that
   * pretends.
   */
  batch(statements: FakeStatement[]): { success: boolean; results: unknown[] }[] {
    this.sqlite.exec('BEGIN')
    try {
      const out = statements.map((s) => {
        s.run()
        return { success: true, results: [] }
      })
      this.sqlite.exec('COMMIT')
      return out
    } catch (error) {
      this.sqlite.exec('ROLLBACK')
      throw error
    }
  }
}

class FakeStatement {
  constructor(
    private readonly sqlite: DatabaseSync,
    private readonly sql: string,
    private readonly params: unknown[] = [],
  ) {}

  /**
   * Returns a NEW statement, because D1's prepared statements are immutable and
   * `bind()` there does the same. A version of this that mutated and returned
   * `this` looked identical for the chained `prepare().bind().all()` calls that
   * the relay used to make, and silently broke the moment one prepared
   * statement was bound repeatedly to build a batch: every row in the batch
   * became the last one.
   */
  bind(...params: unknown[]): FakeStatement {
    return new FakeStatement(this.sqlite, this.sql, params)
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
