#!/usr/bin/env node
// ocu-db.js — project id rotation for OpenCode's sqlite db (Termux port)
// usage: node ocu-db.js rotate <db> [dir] | clean <db> | status <db>

const { DatabaseSync } = require("node:sqlite")
const { randomBytes } = require("node:crypto")
const path = require("node:path")

function open(file) {
  const db = new DatabaseSync(file)
  db.exec("pragma busy_timeout = 5000")
  return db
}

function tables(db) {
  return db.prepare("select name from sqlite_master where type = ?").all("table").map((r) => r.name)
}

function columns(db, table) {
  return db.prepare("pragma table_info(" + table + ")").all().map((c) => c.name)
}

function norm(value) {
  return String(value ?? "").replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase()
}

function carriers(db) {
  return tables(db).filter((t) => columns(db, t).includes("project_id"))
}

function rotate(db, want) {
  const all = tables(db)
  if (!all.includes("project")) {
    console.log("no project table in this database")
    return 3
  }

  let only = null
  if (want) {
    if (!all.includes("project_directory")) {
      console.log("no project_directory table, cannot resolve " + want)
      return 3
    }
    const target = norm(want)
    const rows = db
      .prepare("select project_id, directory from project_directory")
      .all()
      .filter((r) => {
        const dir = norm(r.directory)
        return dir === target || dir.startsWith(target + "/")
      })
    const ids = [...new Set(rows.map((r) => r.project_id))]
    if (ids.length !== 1) {
      if (ids.length === 0) {
        console.log("no project matches: " + want)
        const known = db.prepare("select directory from project_directory order by directory").all()
        for (const row of known) console.log("  " + row.directory)
      } else {
        console.log("ambiguous, " + ids.length + " projects match: " + want)
      }
      return ids.length === 0 ? 3 : 4
    }
    only = ids[0]
  }

  const projects = only
    ? db.prepare("select id from project where id = ?").all(only)
    : db.prepare("select id from project where id != ?").all("global")
  if (!projects.length) {
    console.log("project row missing for " + only)
    return 5
  }

  const keyed = carriers(db)
  db.exec("begin")
  db.exec("pragma defer_foreign_keys = on")
  let renamed = 0
  let touched = 0
  for (const project of projects) {
    const next = randomBytes(20).toString("hex")
    db.prepare("update project set id = ? where id = ?").run(next, project.id)
    for (const table of keyed) {
      const key = table === "project" ? "id" : "project_id"
      const info = db.prepare("update " + table + " set " + key + " = ? where " + key + " = ?").run(next, project.id)
      touched += Number(info.changes || 0)
    }
    renamed += 1
  }
  db.exec("commit")
  console.log("projects rotated: " + renamed + ", rows updated: " + touched)
  return 0
}

function clean(db) {
  let removed = 0
  for (const table of tables(db)) {
    const cols = columns(db, table).filter((c) => c !== "id" && c !== "session_id")
    if (!cols.length) continue
    const where = cols.map((c) => c + " like ?").join(" or ")
    const args = cols.map(() => "%FreeUsageLimitError%")
    try {
      const info = db.prepare("delete from " + table + " where " + where).run(...args)
      removed += Number(info.changes || 0)
    } catch {
      // tables without text columns or with triggers fail here; nothing to clean
    }
  }
  console.log("stuck limit rows removed: " + removed)
  return 0
}

function status(db, want) {
  const all = tables(db)
  const lines = ["tables: " + all.length]
  if (all.includes("project")) {
    const projects = db.prepare("select id, worktree from project order by worktree").all()
    lines.push("projects: " + projects.length)
    for (const p of projects) {
      const dirs = all.includes("project_directory")
        ? db.prepare("select directory from project_directory where project_id = ?").all(p.id).map((r) => r.directory)
        : []
      lines.push("  " + p.id + "  " + (p.worktree ?? "") + (dirs.length ? "  [" + dirs.join(", ") + "]" : ""))
    }
  }
  if (want && all.includes("project_directory")) {
    const target = norm(want)
    const hits = db.prepare("select project_id, directory from project_directory").all().filter((r) => {
      const dir = norm(r.directory)
      return dir === target || dir.startsWith(target + "/")
    })
    lines.push("match: " + JSON.stringify(hits))
  }
  console.log(lines.join("\n"))
  return 0
}

const [cmd, file, arg] = process.argv.slice(2)
if (!cmd || !file) {
  console.log("usage: ocu-db.js rotate <db> [dir] | clean <db> | status <db> [dir]")
  process.exit(2)
}

let db
try {
  db = open(path.resolve(file))
} catch (error) {
  console.log("cannot open " + file + ": " + error.message)
  process.exit(2)
}

let code = 0
if (cmd === "rotate") code = rotate(db, arg)
else if (cmd === "clean") code = clean(db)
else if (cmd === "status") code = status(db, arg)
else {
  console.log("unknown command: " + cmd)
  code = 2
}
db.close()
process.exit(code)
