class AmazonScrapeService
    require 'yaml'

    def initialize(url: nil, asin: nil)
        @product = Product.new
        @selectors = YAML.load_file(Rails.root.join('config', 'scraper', 'selectors.yml'))
        # copy from chrome, temporarily used to avoid being blocked from amazon scraper detector
        @headers = {
          "Host" => "www.amazon.com",
          "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:125.0) Gecko/20100101 Firefox/125.0",
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
          "Accept-Language" => "en-US,en;q=0.5",
          "Accept-Encoding" => "gzip, deflate, br",
          "Alt-Used" => "www.amazon.com",
          "Connection" => "keep-alive",
          "Cookie" => "csm-hit=tb:SBTN1FHZ401B72EVPHDH+s-SBTN1FHZ401B72EVPHDH|1714913684082&t:1714913684082&adb:adblk_yes; session-id=139-8796232-9946603; session-id-time=2082787201l; i18n-prefs=USD; sp-cdn=\"L5Z9:CN\"; ubid-main=132-7102007-7423562; session-token=opHYNxCN5jk11sKwGoPQOHqmPc2H9lehkkFOoY3OBq2ivfwt1Eu2i27NNqiiOAUU25fCtgPDuxoR7uzQ2h35ZoCWhxJVNmOWBi+2aQmn0oLnwoeK31qNnzbvOkQjQ8v/e0zPQcW0brO72446eWpMIriaHghW8HXY/SsUgaZ1Xfzoqx4zsrLC9XNeSYrEXtPMS5hQ8513UTOjuCzLHWEFlSrhoC4K9psPQ04UlYaFJrK7vMBYnxiLU3glwzthQqmYza/x6GixqSRrAkRjvSt+bzajE+dyB7/IIiEbNJwD7giFCqrHGnbtbtgbeymJJak60kGdHQOMTrE6R/b8fdw1AiKyUflFcOqj",
          "Upgrade-Insecure-Requests" => "1",
          "Sec-Fetch-Dest" => "document",
          "Sec-Fetch-Mode" => "navigate",
          "Sec-Fetch-Site" => "none",
          "Sec-Fetch-User" => "?1"
        }

        @asin = extract_asin(url) if url.present?
        return @product.errors.add(:base, 'invalid amazon produnct URL') if @asin.nil?

        # asin redis key
        @asin_key = "asin:#{@asin}"
        # remove redundant elements after asin
        @url = url.split(@asin).first + @asin
        @parsed_data = { name: nil, brand: nil, origin_price: nil, description: nil, images: [], asin: @asin, amazon_link: @url }
    end

    def fetch_data
        return @product if @product.errors.any?

        begin
          response = RestClient.get(@url, headers: @headers)
        rescue => e
          @product.errors.add(:base, "Request has been blocked by amazon, errrors: #{ e.message }")
          return @product
        end

        # record already exists in database
        record = Product.find_by(asin: @asin)
        return record if record

        # reduce the probability of being blocked from amazon scraper detector by reducing the request frequency
        # It is only a temporary solution and can not radically eliminate this issue
        # More complex and advanced mechanism should be imported to address this issue
        html = Rails.cache.fetch(@asin_key , expires_in: 1.day) do
          response.body
        end

        extract_data(html)
        # if empty html cached, delete it
        Rails.cache.delete(@asin_key) if @parsed_data[:name].nil?
        post_process
        @product.assign_attributes(**@parsed_data)
        @product
    end

    def save_data
      record = Product.find_by(asin: @asin)
      return record if record
      return @product if @product.errors.any?

      html = Rails.cache.read(@asin_key)
      return @product if html.nil?

      extract_data(html)
      post_process
      @product.assign_attributes(**@parsed_data)
      @product
    end

    private

    def extract_asin(url)
      return nil unless url.is_a?(String)
      return nil unless url.start_with?('https://www.amazon.com')
      match = url.match(/\/dp\/([A-Z0-9]{10})/)
      asin = match ? match[1] : nil
    end

    def extract_data(html)
        page = Nokogiri::HTML(html)
        @selectors.each do |key, value|
          key = key.to_sym
          if value['type'] == 'Text'
            @parsed_data[key] = page.at_css(value['css'])&.text&.strip
          elsif value['type'] == 'Attribute'
            element = page.css(value['css']).first
            @parsed_data[key] = element ? element[value['attribute']].strip : nil
          elsif value['type'] == 'Link'
            element = page.css(value['css']).first
            @parsed_data[key] = element ? element['href'].strip : nil
          end
        end
    end

    def post_process
      price = @parsed_data.delete(:origin_price)
      @parsed_data[:origin_price] = price.split('$').last.to_f if price.present?
      images = @parsed_data.delete(:images)
      @parsed_data[:images] = JSON.parse(images).keys if images.present?
      brand = @parsed_data.delete(:brand)
      @parsed_data[:brand] = extract_brand(brand) if brand.present?
      short_description = @parsed_data.delete(:short_description).to_s
      product_description = @parsed_data.delete(:product_description).to_s
      @parsed_data[:description] = short_description + ' ' + product_description
      @parsed_data
    end

    # example: "Visit the Kasa Smart Store"
    # example: "Visit the Apple Store"
    def extract_brand(phrase)
      # Use a regular expression to capture the brand name preceding the word 'store'
      match = phrase.match(/Visit the (.+?) store/i)
      # Return the captured brand name or nil if no match is found
      match ? match[1] : phrase
    end
end