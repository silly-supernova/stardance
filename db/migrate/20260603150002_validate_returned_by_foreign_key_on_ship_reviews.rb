class ValidateReturnedByForeignKeyOnShipReviews < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :certification_ship_reviews, :users, column: :returned_by_id
  end
end
