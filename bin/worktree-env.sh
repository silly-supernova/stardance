#!/usr/bin/env sh
# Per-worktree dev environment: gives each git worktree its own, *stable* web
# and database ports plus a matching DATABASE_URL, so many worktrees (and the
# agents working in them) can run side by side without fighting over :3000 /
# :5432.
#
#   . bin/worktree-env.sh          # source it: sets WEB_PORT/DB_PORT/DATABASE_URL
#   bin/worktree-env.sh --print    # emit them as KEY=value (for non-shell callers)
#
# Ports are derived deterministically from the worktree directory name, so the
# same worktree always lands on the same ports. Pre-set values are respected
# (e.g. PORT/DATABASE_URL injected by docker-compose), so this is a no-op there.

_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WORKTREE_SLUG="$(basename "$_root")"

# Stable hash of the worktree name -> offset in [0, 1000).
_off=$(( $(printf '%s' "$WORKTREE_SLUG" | cksum | cut -d' ' -f1) % 1000 ))
_web_base=$(( 3000 + _off ))
_db_base=$(( 5432 + _off ))

_port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
_next_free() {
  _p="$1"
  while _port_busy "$_p"; do _p=$(( _p + 1 )); done
  printf '%s' "$_p"
}

# DB port: if this worktree's compose db container already exists, reuse the
# exact host port Docker assigned it (so DATABASE_URL never drifts); otherwise
# take the deterministic port, stepping past it only if something else holds it.
DB_PORT=""
if command -v docker >/dev/null 2>&1; then
  DB_PORT="$(docker compose port db 5432 2>/dev/null | sed -nE 's/.*:([0-9]+)$/\1/p')"
fi
[ -z "$DB_PORT" ] && DB_PORT="$(_next_free "$_db_base")"

# Web port: native puma process, deterministic with free-port fallback for the
# rare case two worktree names hash to the same base.
WEB_PORT="$(_next_free "$_web_base")"

# Respect an injected DATABASE_URL (e.g. the docker-compose web service points at
# the "db" hostname); otherwise native Rails reaches the container on localhost.
: "${DATABASE_URL:=postgresql://postgres:pass@localhost:${DB_PORT}/stardance_development}"

export WORKTREE_SLUG WEB_PORT DB_PORT DATABASE_URL

if [ "$1" = "--print" ]; then
  printf 'WORKTREE_SLUG=%s\nWEB_PORT=%s\nDB_PORT=%s\nDATABASE_URL=%s\n' \
    "$WORKTREE_SLUG" "$WEB_PORT" "$DB_PORT" "$DATABASE_URL"
fi
