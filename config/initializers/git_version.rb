# stderr is redirected to /dev/null because this runs on every boot: inside the
# Docker container (and other detached checkouts) the worktree's .git pointer
# can't be resolved, and git's "fatal: not a git repository" would otherwise be
# printed before the rescue swallows the Ruby-level error — spamming every
# `bin/rails`/test run. SOURCE_COMMIT (set in prod images) skips git entirely.
git_hash = ENV["SOURCE_COMMIT"] || `git rev-parse HEAD 2>/dev/null`.strip rescue "unknown"
git_hash = "unknown" if git_hash.empty?
commit_link = git_hash != "unknown" ? "https://github.com/hackclub/stardance/commit/#{git_hash}" : nil
short_hash = git_hash[0..7]
is_dirty = `git status --porcelain 2>/dev/null`.strip.length > 0 rescue false
version = is_dirty ? "#{short_hash}-dirty" : short_hash

Rails.application.config.server_start_time = Time.current
Rails.application.config.git_version = version
Rails.application.config.commit_link = commit_link
Rails.application.config.user_agent = "Stardance/#{version} (https://github.com/hackclub/stardance)"
