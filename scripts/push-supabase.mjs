// Applies all SQL migrations in supabase/migrations/ to the remote Supabase project
// using the Supabase Management API (requires SUPABASE_ACCESS_TOKEN = sbp_...).
// Also generates supabase/full_setup.sql for one-click SQL Editor paste.

import { readdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const migrationsDir = path.join(root, 'supabase', 'migrations')
const projectRef = process.env.SUPABASE_PROJECT_REF || 'fgbfqkignouqfbjcmyvr'
const token = process.env.SUPABASE_ACCESS_TOKEN
const only = process.argv[2]

const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort()
const parts = []
for (const f of files) {
  const sql = await readFile(path.join(migrationsDir, f), 'utf8')
  parts.push(`-- >>> ${f}\n${sql}`)
}
const combined = parts.join('\n\n')
const fullSetupPath = path.join(root, 'supabase', 'full_setup.sql')
await writeFile(fullSetupPath, combined, 'utf8')
console.log(`Generated ${fullSetupPath} (${(combined.length / 1024).toFixed(1)} KB)`)

if (!token) {
  console.log('No SUPABASE_ACCESS_TOKEN provided; skipping remote Management API push.')
  process.exit(0)
}

for (const f of files) {
  if (only && !f.includes(only)) continue
  const sql = await readFile(path.join(migrationsDir, f), 'utf8')
  console.log(`Applying ${f} to ${projectRef}...`)
  const res = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/database/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query: sql }),
  })
  if (!res.ok) {
    const text = await res.text()
    console.error(`Failed on ${f}: HTTP ${res.status}\n${text}`)
    process.exit(1)
  }
  console.log(`✓ ${f} applied`)
}

console.log('Done!')
