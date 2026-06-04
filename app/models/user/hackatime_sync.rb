module User::HackatimeSync
  extend ActiveSupport::Concern

  def all_time_coding_seconds
    try_sync_hackatime_data!&.dig(:projects)&.values&.sum || 0
  end

  def try_sync_hackatime_data!(force: false)
    return @hackatime_data if @hackatime_data && !force
    return nil unless hackatime_identity

    result = HackatimeService.fetch_stats(hackatime_identity.uid, access_token: hackatime_identity.access_token)
    return nil unless result

    if result[:banned] && !banned?
      Rails.logger.warn "User #{id} (#{slack_id}) is banned on Hackatime, auto-banning"
      ban!(reason: "Automatically banned: User is banned on Hackatime")
    end

    if result[:projects].any?
      User::HackatimeProject.insert_all(
        result[:projects].keys.map { |name| { user_id: id, name: name } },
        unique_by: [ :user_id, :name ]
      )
    end

    @hackatime_data = result
  end
end
