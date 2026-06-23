# bin/rails streaks:backfill

namespace :streaks do
  desc "Backfill streak activities from Hackatime for all eligible users"
  task backfill: :environment do
    users = User.joins(:hackatime_identity)
                .joins(:hackatime_projects)
                .where.not(user_hackatime_projects: { project_id: nil })
                .distinct

    total = users.count
    puts "Backfilling streak activities for #{total} user(s)..."
    puts

    filled = 0
    skipped = 0
    errored = 0

    users.find_each.with_index(1) do |user, i|
      count = StreakActivity.backfill_for_user!(user, throttle: 0.25)
      if count.nil?
        skipped += 1
        puts "  [#{i}/#{total}] #{user.display_name || user.id} — skipped"
      elsif count.zero?
        skipped += 1
        puts "  [#{i}/#{total}] #{user.display_name || user.id} — already up to date"
      else
        filled += 1
        puts "  [#{i}/#{total}] #{user.display_name || user.id} — backfilled #{count} day(s)"
      end

      sleep 1
    rescue => e
      errored += 1
      puts "  [#{i}/#{total}] #{user.display_name || user.id} — ERROR: #{e.message}"
    end

    puts
    puts "Done. #{filled} backfilled, #{skipped} skipped, #{errored} errored."
  end
end
