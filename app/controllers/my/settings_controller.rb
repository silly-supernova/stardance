class My::SettingsController < ApplicationController
  def update
    authorize :my, :update_settings?

    current_user.update(hcb_email: params[:hcb_email].presence)
    current_user.preference.update!(
      send_votes_to_slack: params[:send_votes_to_slack] == "1",
      leaderboard_optin: params[:leaderboard_optin] == "1",
      search_engine_indexing_off: params[:search_engine_indexing_off] == "1"
    )
    redirect_back fallback_location: root_path, notice: "Settings saved"
  end
end
