# Stardance Agent Instructions

## Environment

Check with the user if the local setup uses docker. If so run anything using `docker compose run --service-ports web COMMAND`.
You can't run in an interactive docker shell but you can execute one-off commands.

## Local setup on Apple Silicon / prod mirror

### Turnkey per-worktree dev (start here)

`bin/setup` (first time) then `bin/dev` (every run after) is all you need — both
are worktree-aware so many worktrees run side by side without colliding:

- **Own ports per worktree, deterministically.** `bin/worktree-env.sh` hashes the
  worktree directory name into a stable web port (`3000+`) and db port (`5432+`),
  falling back to the next free port on the rare hash collision. `bin/dev` prints
  the URL it chose; run `bin/worktree-env.sh --print` to see the assignment
  without starting anything.
- **Own Postgres container per worktree.** Each worktree is already its own
  Docker Compose *project* (named after its directory), so `docker compose up -d
  db` makes an isolated container + volume; the host port is now `${DB_PORT}`
  (set by the helper) instead of a hardcoded `5432`, which is what used to let
  only one worktree's db run at a time. `bin/setup`/`bin/dev` bring it up and
  point `.env`'s `DATABASE_URL` at `localhost:$DB_PORT` automatically.
- **Toolchain is auto-selected.** Recent mise does NOT auto-activate from
  `.ruby-version`, so the project's scripts re-exec themselves under
  `mise exec ruby@<.ruby-version> node@<.node-version>` (see `bin/toolchain.rb`).
  This now covers `bin/setup`, `bin/dev`, **and** the binstubs you reach for
  directly — `bin/rails`, `bin/rake`, `bin/bundle`, `bin/rubocop`, `bin/brakeman`,
  `bin/lint` — so `bin/rails test` from a fresh shell Just Works. **Always go
  through `bin/*`, never the bare binary:** a bare `ruby`/`bundle` hits the macOS
  system Ruby 2.6 and dies with ``\`windows\` is not a valid platform``; bare
  `yarn` is the wrong version or missing (use `corepack yarn`); `psql` isn't on
  the host (use `docker compose exec db psql`). If you must invoke a tool with no
  binstub, prefix it with `mise exec ruby@<.ruby-version> node@<.node-version> --`.

Things below are what the docs/README don't tell you. Keep host-specific Docker
fixes in the (now gitignored) **`docker-compose.override.yml`** so the committed
config and `Gemfile.lock` stay clean.

- **`.env` is required and not checked in.** A fresh checkout/worktree has no
  `.env` — `cp example.env .env` (its dev keys work; `dotenv-rails` loads it from
  the mounted volume). **Worktrees should pull from the parent repo's `.env`**:
  `PROD_DATABASE_URL` (and other real secrets) live in the parent repo's `.env`,
  not in the worktree's copy, so source/copy those over rather than assuming the
  worktree is self-contained.
- **arm64 build break.** The web image won't build natively — `bundle install`
  exits 7 because `Gemfile.lock` has no `aarch64-linux` platform and `sqlite-vec`
  ships no arm64-linux build. Fix without touching the lockfile: build web as
  `platform: linux/amd64` (runs under Rosetta — slower, but `x86_64-linux` is
  fully in the lockfile).
- **Postgres version mismatch.** Prod is Postgres 18.x but `docker-compose.yml`
  pins `pgvector/pgvector:pg16`. `pg_dump` can't read a newer server and a
  downgrade restore is risky, so to load a prod mirror bump the local db to
  `pgvector/pgvector:pg18`. The pg18 image refuses data mounted directly at
  `/var/lib/postgresql/data`, so also set `PGDATA=/var/lib/postgresql/data/pgdata`.
- **You don't need a full dump or prod encryption keys for a usable mirror.**
  ~95% of prod is analytics noise (`active_insights_requests`/`jobs`, `versions`,
  `vote_events`, `post_views`). `pg_dump --exclude-table-data` on those yields
  ~250 MB with users/posts/devlogs/projects intact. `users.email`/`display_name`
  are plaintext (Lockbox only covers identities/credentials/shop tables, which
  timeline/post rendering never touches), so it renders fine with the
  `example.env` dev keys.
- **Dev login (dev/test only):** `GET /dev_login/:id` signs you in as that user;
  `DEV_ADMIN_USER_ID` is the no-id default.
- **Reaching it over Tailscale:** Rails dev host-authorization returns `403
  "Blocked hosts"` for unknown hosts. The match includes the port and the
  leading-dot shorthand (`.ts.net`) doesn't match. Rails 8.1 reads a native
  `RAILS_DEVELOPMENT_HOSTS` env var — set your tailnet host there in `.env`
  rather than editing `development.rb`. Docker already publishes 3000 on
  `0.0.0.0`, so the tailnet can reach it.
- **First-boot gotchas:** `docker compose up -d web` may try to rebuild, and a
  tail-piped command's exit code can mask a build failure — check that the image
  actually exists, not just the pipe's `exit 0`. First boot compiles assets, so
  HTTP 200 lags container start by ~10–20s.

## Build & Test Commands

- **Run all tests**: `bin/rails test`
- **Lint & Fix**: `bin/lint`
- **Run CI locally (mirror of GitHub Actions)**: `bin/ci-local`
- **Start dev server**: `bin/dev`
- **Database setup**: `bin/rails db:prepare`

## PR workflow off `improved-agent-experience`

This branch line (`improved-agent-experience` and its worktree branches like the
randomly-named `dramatic-lark`) carries **dev/agent tooling only** — `bin/*`
toolchain shims, per-worktree dev setup, `docker-compose` tweaks, this file, etc.
Its entire diff vs `main` is that tooling. We develop features on top of it so we
get the ergonomics, but **that tooling must never end up in a feature PR**. When
opening a PR, follow these steps in order — do not skip any.

### 1. Start from latest `main`, not from the tooling branch

Pull the latest `main` into the working branch first, so we build on current main
*and* keep the agent-experience tooling locally:

```bash
git fetch origin
git merge origin/main          # incorporate latest main into this branch
```

Resolve any conflicts before continuing. The goal: this branch = latest `main` +
agent tooling + your feature work.

### 2. Code-quality review before finishing

Before preparing the push, review the diff against repo conventions (see **Code
Style & Conventions** above and `docs/branding.md` for visual work). Check for:

- No unnecessary or dead code, no leftover debug logging, no commented-out blocks.
- No gratuitous comments — comments explain *why*, not *what*; match the
  surrounding file's density.
- Rails/omakase RuboCop style, BEM SCSS, CSS classes instead of `style=` attrs,
  reuse of existing components/partials.
- Pundit policies on new controller actions; PaperTrail + audit logging on admin
  changes; `lockbox`/`blind_index` on new encrypted fields.
- Migrations created via `bin/rails generate migration` (never hand-written), and
  **confirmed with the user** before running.

Run `bin/lint` to auto-fix formatting, then re-read the diff.

### 3. Run CI locally before pushing

GitHub Actions (`.github/workflows/ci.yml`) gates the PR. Run the same checks
locally first and get them green:

```bash
docker compose up -d db   # db_checks need the test database
bin/ci-local
```

`bin/ci-local` mirrors every `ci.yml` job (Brakeman, RuboCop, ERB Lint, Prettier
JS/TS + SCSS, Zeitwerk, schema-up-to-date, annotations). Do not push until it
exits green. (`build.yml` is deploy-only and runs only on push to `main` — not
part of PR verification.) If the local setup uses Docker, wrap commands per the
**Environment** section (`docker compose run --service-ports web ...`).

### 4. Push only the feature diff — exclude the tooling

The PR must contain **only the diff between `main` and your feature work** — never
the `improved-agent-experience` tooling commits. Create a properly-named branch
(`feat/...`, `fix/...`, `chore/...`, `docs/...` — never the random worktree name)
and replay only your feature commits onto `main`:

```bash
git fetch origin
git branch feat/descriptive-name HEAD        # snapshot current work (keeps this branch intact)
git rebase --onto origin/main origin/improved-agent-experience feat/descriptive-name
git push -u origin feat/descriptive-name
```

`rebase --onto origin/main origin/improved-agent-experience` takes exactly the
commits the work branch has on top of `improved-agent-experience` (your feature)
and replays them onto `main`, dropping the tooling and any already-merged `main`
commits. After the rebase, **verify the tooling is gone** before pushing:

```bash
git diff origin/main...feat/descriptive-name --stat   # should show ONLY feature files,
                                                      # no bin/*, AGENTS.md, docker-compose, worktree-env
```

If tooling files still appear, stop and fix the branch — do not push.

### 5. Open the PR — human writes the description

Push the branch, then **the human writes the PR description, not the agent.** Use
the repo template at `.github/pull_request_template.md` verbatim (the
`what's this do?` / `show it works` / `ai?` sections) and let the human fill it in.
Open it pre-populated with the empty template so they only fill the blanks:

```bash
gh pr create --base main --head feat/descriptive-name \
  --title "<short title>" \
  --body-file .github/pull_request_template.md --web
```

Do not author or auto-fill the PR body. Leave the template sections for the human.

## Architecture & Structure

- **Framework**: Ruby on Rails 8.1.
- **Database**: PostgreSQL with `solid_queue` (jobs).
- **Caching**: Redis (`redis_cache_store`) in production, `memory_store` in development.
- **Key Gems**:
  - `pundit` (Authorization)
  - `aasm` (State Machines)
  - `paper_trail` (Versioning)
  - `flipper` (Feature Flags)
  - `view_component` (UI Components)
- **Deployment**: Coolify (Docker-based), not Kamal.

## Code Style & Conventions

- **Style**: Follows `rubocop-rails-omakase` defaults.
- **Testing**: Use **Minitest** (default Rails testing). Do not use RSpec.
  - Fixtures are used for test data (`test/fixtures/`).
- **Frontend**:
  - Use `esbuild` for JS and `dartsass-rails` for CSS.
  - Place controllers in `app/javascript/controllers`.
- **Security**:
  - Use `lockbox` and `blind_index` for encrypted fields.
  - Ensure `pundit` policies are applied in controllers.

When making changes/creations towards admin sides of the codebase there needs to be proper papertrail code and audit logging which should be accessible.

DB migrations should always ask for user confirmation.

When making code changes that require migrations, always use `bin/rails generate migration` instead of manually creating migration files. Manually creating migrations can cause issues when the AI generates improper migration syntax or timestamps.

Bias for rails generators (ie. rails g model/migration) when first creating a file.

We want maintainable code! Please use proper code formatting and naming conventions, also please use css classes instead of raw `style=` attributes, if possible use already existing components or partials.

When coding please do not produce unnecessary code or any dead code, if u make dead code please make sure to remove it and clean it up!

Please use BEM SCSS styling when writing SCSS: https://getbem.com/introduction/

## Codebase heritage: Flavortown → Stardance

This codebase is being re-used from a previous Hack Club program called
**Flavortown**, which used a brown-wood, food-themed visual identity. The goal
is to turn it into a new program called **Stardance**, which is space-themed and
uses the new branding guidelines (see the theming section below and
[docs/branding.md](docs/branding.md)).

When implementing something:

- **Reuse if clean.** If a previous Flavortown component / partial / helper
  already does what you need and is well-written, prefer reusing it.
- **Otherwise re-implement and purge.** If the old code is messy or tightly
  coupled to the food/wood theme, re-implement it cleanly and delete the old
  system rather than layering on top of it. Don't leave dead Flavortown code
  behind.
- **Always use Stardance branding, never Flavortown.** Anything you implement
  must use the new Stardance branding — even when reusing a component that
  already exists, update it so it uses the new space-themed palette, type, and
  patterns. Never carry the old brown-wood / food styling forward.

## Stardance themeing

The full visual identity spec — palette, type scale, container sets, button
states, form patterns — lives in [docs/branding.md](docs/branding.md). Read it
before doing visual work; it's the source of truth and is mirrored from the
Figma design system page.

Design tokens (background, brand palette, spacing, fonts, font sizes) are defined as CSS variables in [app/assets/stylesheets/config/_variables.scss](app/assets/stylesheets/config/_variables.scss). Reference them via `var(--token-name)` rather than inlining hex / rem values.

Background: `#08061E` (`--color-space-bg` / set on `<html>` in `landing/_base.scss`).

Brand palette — use the `--color-brand-*` variables in code:

- `#81FFFF` — `--color-brand-mint`
- `#EBB7FF` — `--color-brand-lilac`
- `#95DBFF` — `--color-brand-blue`
- `#FF8D9D` — `--color-brand-salmon`
- `#FFE564` — `--color-brand-yellow`
- `#FFD598` — `--color-brand-peach`
- `#FFF8D5` — `--color-brand-cream`
- `#FFFCF4` — `--color-brand-off-white`
- `#FFB07A` — `--color-brand-orange` — **reserved**: admin / manageable-by-viewer marker only (2px dashed border, see [docs/branding.md §1.5](docs/branding.md)). Don't use it for general accents.

When trying to choose a color, please try to choose from one of the colors above by default. If not, you can fall back to similar pastel colors. Try to avoid colors that are too saturated / deep. See [docs/branding.md](docs/branding.md) for the four "set" container surfaces, highlight tones, and which accent applies where.

For the font, use Exo 2 for most body text and title text, with emphasis being in Playfair Display italics. The full type scale (Title, Title 2, Heading, Small heading, Body, Label) with sizes and weights is documented in [docs/branding.md](docs/branding.md).