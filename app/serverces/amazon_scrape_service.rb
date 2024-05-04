class AmazonScrapeService
    require 'yaml'

    def initialize(url)
        @selectors = YAML.load_file(Rails.root.join('config', 'scraper', 'selectors.yml'))
        @headers = {
            'DNT' => '1',
            'Upgrade-Insecure-Requests' => '1',
            'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.61 Safari/537.36',
            'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
            'Sec-Fetch-Site' => 'same-origin',
            'Sec-Fetch-Mode' => 'navigate',
            'Sec-Fetch-User' => '?1',
            'Sec-Fetch-Dest' => 'document',
            'Referer' => 'https://www.amazon.com/',
            'Accept-Language' => 'en-GB,en-US;q=0.9,en;q=0.8'
        }

        # extract asin
        @asin = extract_asin(url)
        raise 'invalid amazon produnct URL' if @asin.nil?

        # asin redis key
        @asin_key = "asin:#{@asin}"
        # remove redundant elements after asin
        @url = url.split(@asin).first + @asin
    end

    def scrape
        response = RestClient.get(@url, headers: @headers)
        if response.code != 200
          puts "Page #{@url} must have been blocked by Amazon as the status code was #{response.code}"
          return nil
        end

        product = Product.find_by(asin: @asin)
        # already exists in database
        return product.attributes.deep_symbolize_keys if product

        # reduce the probability of being blocked from amazon scraper detector by reducing the request frequency
        # It is only a temporary solution and can not radically eliminate this issue
        # More complex and advanced mechanism should be imported to address this issue
        html = Rails.cache.fetch(@asin_key , expires_in: 1.day) do
          response.body
        end

        extract_data(html)
    end

    private

    def extract_asin(url)
      match = url.match(/\/dp\/([A-Z0-9]{10})/)
      match ? match[1] : nil
    end

    def extract_data(html)
        page = Nokogiri::HTML(html)
        data = {}
        @selectors.each do |key, value|
          if value['type'] == 'Text'
            data[key] = page.css(value['css']).text.strip
          elsif value['type'] == 'Attribute'
            element = page.css(value['css']).first
            data[key] = element ? element[value['attribute']].strip : nil
          elsif value['type'] == 'Link'
            element = page.css(value['css']).first
            data[key] = element ? element['href'].strip : nil
          end
        end
        data
    end
end