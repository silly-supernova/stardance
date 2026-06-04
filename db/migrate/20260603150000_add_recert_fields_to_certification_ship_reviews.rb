class AddRecertFieldsToCertificationShipReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :certification_ship_reviews, :recert_reason, :text unless column_exists?(:certification_ship_reviews, :recert_reason)
    add_column :certification_ship_reviews, :returned_by_id, :bigint unless column_exists?(:certification_ship_reviews, :returned_by_id)
    unless index_exists?(:certification_ship_reviews, :returned_by_id)
      add_index :certification_ship_reviews, :returned_by_id, algorithm: :concurrently
    end
    unless foreign_key_exists?(:certification_ship_reviews, column: :returned_by_id)
      add_foreign_key :certification_ship_reviews, :users, column: :returned_by_id, validate: false
    end
  end
end
