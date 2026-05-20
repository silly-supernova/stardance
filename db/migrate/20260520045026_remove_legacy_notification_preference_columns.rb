class RemoveLegacyNotificationPreferenceColumns < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :user_preferences, :send_notifications_for_new_followers,     :boolean, default: true, null: false
      remove_column :user_preferences, :send_notifications_for_followed_projects, :boolean, default: true, null: false
      remove_column :user_preferences, :send_notifications_for_new_comments,      :boolean, default: true, null: false
      remove_column :user_preferences, :send_notifications_for_followed_users,    :boolean, default: true, null: false
      remove_column :user_preferences, :stardust_balance_notifications,           :boolean, default: false, null: false
      remove_column :users,            :mission_review_notifications,             :boolean, default: true, null: false
    end
  end
end
