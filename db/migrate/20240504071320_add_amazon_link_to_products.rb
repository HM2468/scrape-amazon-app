class AddAmazonLinkToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :amazon_link, :string
  end
end
