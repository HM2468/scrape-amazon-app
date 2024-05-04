class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.string :name
      t.string :brand
      t.float :origin_price
      t.text :description
      t.string :asin
      t.string :images, array: true, default: []  # Array of strings for images
      t.timestamps
    end

    # Add a unique index to the asin column to ensure no duplicates are allowed
    add_index :products, :asin, unique: true
  end
end
