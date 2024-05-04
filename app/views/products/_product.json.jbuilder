json.extract! product, :id, :name, :brand, :origin_price, :description, :amazon_link
json.url product_url(product, format: :json)
