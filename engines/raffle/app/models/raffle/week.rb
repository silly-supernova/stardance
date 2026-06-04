module Raffle
  class Week < ApplicationRecord
    has_paper_trail

    has_many :credited_referrals, class_name: "Raffle::Referral",
             foreign_key: :credited_week_id, dependent: :nullify, inverse_of: :credited_week
    has_many :signup_participants, class_name: "Raffle::Participant",
             foreign_key: :signup_week_id, dependent: :nullify, inverse_of: :signup_week
    belongs_to :winner_participant, class_name: "Raffle::Participant", optional: true

    enum :status, { active: "active", archived: "archived" }, prefix: :status

    validates :status, presence: true
    validates :number, presence: true, uniqueness: true,
              numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 16 }

    scope :chronological, -> { order(:number) }

    def self.current
      status_active.take
    end

    # { participant_id => total_entries } for this week.
    # Base entry (1) for participants who signed up this week +
    # 20 per verified referral credited to this week.
    def standings
      base = signup_participants.where(eligible: true).pluck(:id).each_with_object({}) do |pid, h|
        h[pid] = 1
      end

      referral_counts = credited_referrals.status_verified
                                          .group(:participant_id)
                                          .count

      referral_counts.each do |pid, count|
        base[pid] = (base[pid] || 0) + (count * 20)
      end

      base
    end

    def leaderboard(limit: 25, standings: self.standings)
      ranked = standings.sort_by { |_id, entries| -entries }
      return [] if ranked.empty?

      participants = Raffle::Participant.includes(:user).where(id: ranked.map(&:first)).index_by(&:id)
      ranked.filter_map { |id, entries| [ participants[id], entries ] if participants[id] }
            .first(limit)
    end

    def rank_for(participant, standings: self.standings)
      return nil unless participant

      mine = standings[participant.id].to_i
      return nil if mine.zero?

      standings.values.count { |entries| entries > mine } + 1
    end

    def participant_count
      standings.size
    end

    def drawn?
      winner_participant_id.present?
    end
  end
end
