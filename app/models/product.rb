class Product < ApplicationRecord
  after_commit :clean_amazon_cache, on: :create

  private

  def clean_amazon_cache
    Rails.cache.delete("asin:#{asin}")
  end
end
