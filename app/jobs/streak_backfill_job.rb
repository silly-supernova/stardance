class StreakBackfillJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    StreakActivity.backfill_for_user!(user)
  end
end
