class Api::V1::AmbassadorReferralsController < Api::V1::BaseController
  BOOLEAN = ActiveModel::Type::Boolean.new
  private_constant :BOOLEAN

  def index
    render json: payload(scope_for_mode)
  end

  def show
    code = params[:id].to_s
    if code.start_with?(Rsvp::AMBASSADOR_REFERRAL_PREFIX)
      render json: payload(scope_for_mode.matching_ref(code))
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  private
    def rsvp_mode?
      BOOLEAN.cast(params[:rsvp])
    end

    def scope_for_mode
      rsvp_mode? ? Rsvp.ambassador_referrals : User.ambassador_referrals
    end

    def payload(scope)
      rsvp_mode = rsvp_mode?
      records = scope.order(:id).to_a
      referrals = rsvp_mode ? rsvp_items(records) : user_items(records)

      {
        prefix: Rsvp::AMBASSADOR_REFERRAL_PREFIX,
        rsvp: rsvp_mode,
        count: referrals.size,
        referrals: referrals
      }
    end

    def user_items(users)
      metrics = AmbassadorReferralMetrics.new(users)

      users.map do |user|
        user.ambassador_referral_payload(
          hours_logged: hours(metrics.logged_seconds[user.id]),
          hours_approved: hours(metrics.approved_seconds[user.id])
        )
      end
    end

    def rsvp_items(rsvps)
      users_by_email = User.matching_emails(rsvps.map(&:email))
                           .index_by { |user| user.email.to_s.downcase }
      metrics = AmbassadorReferralMetrics.new(users_by_email.values)

      rsvps.map do |rsvp|
        user = users_by_email[rsvp.email.to_s.downcase]
        rsvp.ambassador_referral_payload.merge(
          verification_status: user&.verification_status,
          hours_logged: user ? hours(metrics.logged_seconds[user.id]) : nil,
          hours_approved: user ? hours(metrics.approved_seconds[user.id]) : nil
        )
      end
    end

    def hours(seconds)
      ((seconds || 0) / 3600.0).round(2)
    end
end
