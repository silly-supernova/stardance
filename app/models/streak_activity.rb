# == Schema Information
#
# Table name: streak_activities
#
#  id            :bigint           not null, primary key
#  activity_date :date             not null
#  coded_seconds :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :bigint           not null
#
# Indexes
#
#  index_streak_activities_on_user_id                    (user_id)
#  index_streak_activities_on_user_id_and_activity_date  (user_id,activity_date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 300 # 5 minutes

  belongs_to :user

  validates :activity_date, presence: true
  validates :activity_date, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where("coded_seconds >= ?", DAILY_GOAL_SECONDS) }
  scope :for_date, ->(date) { where(activity_date: date) }
  scope :for_range, ->(range) { where(activity_date: range) }

  has_paper_trail

  def completed?
    coded_seconds >= DAILY_GOAL_SECONDS
  end

  class << self
    def sync_for_user!(user)
      return nil unless user.hackatime_identity.present?

      linked_projects = user.hackatime_projects.where.not(project_id: nil)
      return nil if linked_projects.empty?

      project_keys = linked_projects.pluck(:name)
      today = streak_date_for(Time.current, user.timezone)

      seconds = HackatimeService.fetch_total_seconds_for_projects(
        user.hackatime_identity.uid,
        project_keys,
        start_date: today.to_s,
        end_date: (today + 1.day).to_s,
        access_token: user.hackatime_identity.access_token
      )
      return nil if seconds.nil?

      record = find_or_initialize_by(user_id: user.id, activity_date: today)
      record.update!(coded_seconds: seconds)
      record
    end

    def backfill_for_user!(user, throttle: 0)
      cache_key = "streak_backfill_running:#{user.id}"
      return nil unless Rails.cache.write(cache_key, true, expires_in: 10.minutes, unless_exist: true)

      return nil unless user.hackatime_identity.present?

      linked_projects = user.hackatime_projects.where.not(project_id: nil)
      return nil if linked_projects.empty?

      project_keys = linked_projects.pluck(:name)
      today = streak_date_for(Time.current, user.timezone)
      window_start = Date.parse(HackatimeService::START_DATE)

      count = 0
      (window_start...today).each do |date|
        seconds = HackatimeService.fetch_total_seconds_for_projects(
          user.hackatime_identity.uid,
          project_keys,
          start_date: date.to_s,
          end_date: (date + 1.day).to_s,
          access_token: user.hackatime_identity.access_token
        )
        next if seconds.nil?

        record = find_or_initialize_by(user_id: user.id, activity_date: date)
        next if record.persisted? && record.coded_seconds == seconds
        record.update!(coded_seconds: seconds)
        count += 1
        sleep throttle if throttle > 0
      end
      count
    ensure
      Rails.cache.delete(cache_key)
    end

    def streak_date_for(time, timezone)
      tz = timezone.presence || "UTC"
      (time.in_time_zone(tz) - 2.hours).to_date
    end
  end
end
