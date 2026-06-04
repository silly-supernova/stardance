module User::ShopAccess
  extend ActiveSupport::Concern

  def seller? = ShopItem::HackClubberItem.exists?(user_id: id)

  def has_regions?
    regions.present? && regions.any?
  end

  def has_region?(region_code)
    regions.include?(region_code.to_s.upcase)
  end

  def regions_display
    regions.map { |region| Shop::Regionalizable.region_name(region) }.join(", ")
  end

  def reject_pending_orders!(reason: "User banned")
    shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment]).find_each do |order|
      order.mark_rejected(reason)
      order.save!
    end
  end

  def addresses
    addresses = hca_identity_payload["addresses"] || []
    addresses.map { |address| address.merge("phone_number" => hca_identity_payload["phone_number"]) }
  end

  def birthday
    birthday_str = hca_identity_payload["birthday"]
    return nil if birthday_str.blank?

    Date.parse(birthday_str)
  rescue ArgumentError
    nil
  end

  private
    def hca_identity_payload
      @hca_identity_payload ||= if (identity = hack_club_identity)&.access_token.present?
        HCAService.identity(identity.access_token)
      else
        {}
      end
    end
end
