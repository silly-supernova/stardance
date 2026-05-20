class ShipEventPayoutCalculator
  def self.apply!(ship_event)
    new(ship_event).apply!
  end

  def initialize(ship_event, game_constants: Rails.configuration.game_constants)
    @ship_event = ship_event
    @game_constants = game_constants
  end

  def apply!
    return unless @ship_event.current_voting_scale?

    payout_user = @ship_event.payout_recipient
    return unless payout_user

    project = @ship_event.post&.project
    return unless project

    unless payout_eligible?
      if payout_user.vote_balance < 0
        notify_vote_deficit(payout_user, payout_user.vote_balance.abs)
      end
      return
    end

    @ship_event.with_lock do
      return unless payout_eligible?

      hours_used = base_hours
      return if hours_used <= 0

      percentile = @ship_event.overall_percentile
      return if percentile.nil?

      hourly_rate = dollars_per_hour_for_percentile(percentile)

      return if hourly_rate <= 0

      # mult is like if mult is 30 then you have $6/hr. or you get 30 stardust so its how many stardust you get
      mult = (hourly_rate * tickets_per_dollar).round(6)
      is_bridge = apply_legacy_bridge?(project)
      legacy_hours = is_bridge ? (bridge_total_hours(project: project) - hours_used) : 0.0
      payout_hours = is_bridge ? bridge_total_hours(project: project) : hours_used
      legacy_deduction = is_bridge ? project.legacy_payout_total : 0.0
      stardust = calculate_stardust(
        hours: hours_used,
        multiplier: mult,
        legacy_hours: legacy_hours,
        legacy_deduction: legacy_deduction,
        bridge: is_bridge
      )
      return if stardust.nil?

      blessing = payout_user.vote_verdict&.verdict || "neutral"
      stardust  = Secrets::VoteVerdictMultiplier.apply(stardust, blessing)

      ActiveRecord::Base.transaction do
        attrs = {
          payout: stardust,
          multiplier: mult,
          hours: payout_hours,
          bridge: is_bridge,
          base_hours: hours_used,
          legacy_payout_deduction: is_bridge ? legacy_deduction : nil,
          payout_blessing: blessing
        }

        @ship_event.update!(attrs)

        if stardust.positive?
          payout_user.ledger_entries.create!(
            ledgerable: @ship_event,
            amount: stardust,
            reason: build_payout_reason(project: project, bridge: is_bridge, new_hours: hours_used, legacy_hours: legacy_hours, legacy_deduction: legacy_deduction),
            created_by: "ship_event_payout"
          )
        end
      end

      notify_payout_issued(payout_user, stardust: stardust, hours: payout_hours, multiplier: mult, blessing: blessing)
      broadcast_payout(payout_user, stardust, payout_hours, mult)
    end
  end

  private

  BROADCAST_CHANNEL_ID = "C0AFB0JU00P"

  def broadcast_payout(user, stardust, hours, multiplier)
    project = @ship_event.post&.project
    SendSlackDmJob.perform_later(
      BROADCAST_CHANNEL_ID,
      nil,
      blocks_path: "notifications/payouts/broadcast",
      locals: {
        project_title: project&.title || "Unknown",
        project_url: "https://flavortown.hackclub.com/projects/#{project&.id}",
        recipient_name: user.display_name,
        stardust: stardust,
        hours: hours&.round(2),
        multiplier: multiplier&.round(2)
      }
    )
  end

  def payout_eligible?
    @ship_event.payout_eligible?
  end

  def base_hours
    hours = @ship_event.hours
    hours.to_f if hours.present?
  end

  def dollars_per_hour_for_percentile(percentile)
    p = (percentile.to_f / 100.0).clamp(0.0, 1.0)
    low  = lowest_dollar_per_hour   # 0.30
    high = highest_dollar_per_hour  # 6.00
    return 0.0 if high <= 0 || low < 0 || high < low

    gamma = 1.745427173
    rate = low + (high - low) * (p ** gamma)
    rate.clamp(low, high)
  end

  def build_payout_reason(project:, bridge:, new_hours: nil, legacy_hours: nil, legacy_deduction: nil)
    title = project&.title || "Unknown"

    if bridge
      "Bridge payout: #{title} (#{new_hours.to_f.round(2)}h new + #{legacy_hours.to_f.round(2)}h legacy, minus #{legacy_deduction.to_f.round(0)} legacy stardust)"
    else
      "Ship event payout: #{title}"
    end
  end

  def lowest_dollar_per_hour = @game_constants.lowest_dollar_per_hour.to_f
  def highest_dollar_per_hour = @game_constants.highest_dollar_per_hour.to_f
  def dollars_per_mean_hour = @game_constants.dollars_per_mean_hour.to_f
  def tickets_per_dollar = @game_constants.tickets_per_dollar.to_f

  def calculate_stardust(hours:, multiplier:, legacy_hours:, legacy_deduction:, bridge:)
    return nil if multiplier <= 0

    if bridge
      new_hours_stardust = (hours * multiplier).round
      legacy_top_up = ((legacy_hours * multiplier) - legacy_deduction).round.clamp(0, Float::INFINITY)
      new_hours_stardust + legacy_top_up
    else
      stardust = (hours * multiplier).round
      return nil if stardust <= 0

      stardust
    end
  end

  def bridge_total_hours(project:)
    project.total_ship_hours
  end

  def apply_legacy_bridge?(project)
    return false unless project.has_legacy_ship_events?

    !project.has_paid_current_scale_ship_events?(excluding_ship_event_id: @ship_event.id)
  end

  def notify_payout_issued(user, stardust:, hours:, multiplier:, blessing: "neutral")
    project = @ship_event.post&.project
    ship_date = @ship_event.post&.created_at&.strftime("%b %-d, %Y")
    project_title = project&.title || "Ship ##{@ship_event.id}"

    Notifications::Payouts::ShipEventIssued.notify(
      recipient: user,
      record: @ship_event,
      params: {
        "project_title" => project_title,
        "ship_date"     => ship_date,
        "hours"         => hours&.round(2),
        "stardust"      => stardust&.to_i,
        "multiplier"    => multiplier&.round(2),
        "blessing"      => blessing
      }
    )
  end

  def notify_vote_deficit(user, votes_needed)
    return unless Flipper.enabled?(:voting)

    cache_key = "vote_deficit_notified:#{@ship_event.id}"
    return if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: 6.hours)

    project = @ship_event.post&.project
    project_title = project&.title

    Notifications::Payouts::VoteDeficitBlocked.notify(
      recipient: user,
      record: @ship_event,
      params: {
        "votes_needed"  => votes_needed,
        "project_title" => project_title
      }
    )
  end
end
