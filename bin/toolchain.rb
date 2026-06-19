# frozen_string_literal: true

# Re-exec the calling binstub under the project's mise-managed toolchain.
#
# A binstub's shebang picks up whatever `ruby`/`node` is first on PATH, and
# recent mise does NOT auto-activate from .ruby-version. So a bare `bin/rails`
# (or bin/rake / bin/bundle / bin/rubocop ...) from a fresh shell runs on the
# macOS system Ruby 2.6, which can't even parse our Gemfile and dies with
# "`windows` is not a valid platform". bin/dev and bin/setup already guard
# against this; this file extends the same guard to the binstubs people (and
# agents) reach for directly.
#
# Guarded so it happens once, and only when mise is installed (CI, Docker, and
# non-mise contributors fall straight through to their own toolchain). `require`
# this as the very first line of a binstub, before anything touches Bundler.
unless ENV["STARDANCE_TOOLCHAIN"] || !system("command -v mise > /dev/null 2>&1")
  root = File.expand_path("..", __dir__)
  rv = (File.read(File.join(root, ".ruby-version")).strip.sub(/\Aruby-/, "") rescue "3.4.3")
  nv = (File.read(File.join(root, ".node-version")).strip rescue "22")
  exec({ "STARDANCE_TOOLCHAIN" => "1" }, "mise", "exec", "ruby@#{rv}", "node@#{nv}", "--", "ruby", $PROGRAM_NAME, *ARGV)
end
