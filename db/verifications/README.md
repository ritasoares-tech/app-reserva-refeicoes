# Verifications

One script per migration in `../migrations/`, same number. Each is that migration's commented
**VERIFICACAO** block made runnable — the comments in the migrations stay where they are, as the
record; these exist so nobody has to copy and uncomment them.

## How to run one

Paste the **whole file** into the Supabase SQL editor and run it. The editor only shows the result
of the *last* statement, so every script collects its checks into one table and shows that:

| column | meaning |
|---|---|
| `verificacao` | which check, numbered like the block in the migration |
| `obtido` | what the database says |
| `esperado` | what it should say |
| `ok` | `true` / `false` when it can be decided automatically; **empty = read `obtido` and compare** |

## When to run it

**Right after applying its migration, before the next one.** The expected values are the ones
immediately after that migration, and later migrations change some of them on purpose (004's
`avisos-atraso` moves from day 11 to day 9 in 011; 010 drops `definir_contrato_aluno`; the function
count in 001 and 006 grows). Run an early script at the end and those rows show `false` — that is
history, not a fault.

Also:

- **`valores-referencia.sql`** — run **before and after** 008, 010 and 011 and compare the two
  tables: reservations by state, and `saldos_por_aluno` read as the canteen.
- **`011-antes-quem-fica-bloqueado.sql`** — run **before** 011: who the block catches the moment it
  lands. Right after 001 (which empties `meses_em_divida`) it returns nothing.

## What they touch

Nothing permanent. Where a check has to *do* something to prove behaviour — insert a test student
(002), write an invalid value (003), generate reminders (004), create a request (005), purge (006),
change a price (008) — it runs inside a PL/pgSQL block that ends by raising an error on purpose, so
the write is rolled back and only the result is kept. A few checks need data to exist (a
reservation, a lunch menu); without it they say so and leave `ok` empty.

Checks that must run **as the canteen** (`saldos_por_aluno`, the purge) set `request.jwt.claim.sub`
to the first row of `cantina`, only inside the script — the SQL editor has no `auth.uid()` of its
own, and those functions refuse without one.

Each script creates a temporary table `_verificacao`; it disappears when the editor's session ends.

## Keeping them honest

`tests/verificacoes.ts` (local, git-excluded) runs any of them against the **test copy** and prints
the table: `cd tests && bun run verificacoes.ts 011`. The copy has every migration applied, so read
the early ones with the note above in mind. If a migration's commented block changes, change its
script too.
