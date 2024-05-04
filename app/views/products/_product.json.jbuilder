json.extract! product, :name, :brand, :origin_price, :description, :amazon_link
json.url product_url(product, format: :json)
