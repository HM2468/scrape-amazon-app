class AmazonScrapeService
    require 'yaml'

    def initialize(url)
        @selectors = YAML.load_file(Rails.root.join('config', 'scraper', 'selectors.yml'))

        # copy from chrome, temporarily used to avoid being blocked from amazon scraper detector
        @headers = {
          'accept' =>  '*/*',
          'Accept-Encoding' =>  'gzip, deflate, br, zstd',
          'Accept-Language' =>  'zh,zh-CN;q=0.9,en;q=0.8',
          'Connection' =>  'keep-alive',
          'Content-Type' =>  'text/plain;charset=UTF-8',
          'Cookie' =>  'session-id=131-1598766-4889943; skin=noskin; ubid-main=131-6778161-0238132; x-main="bxv0rssmii0ENFZ2P54O74FvEOoOqrjx?7nW5Xp03RXVIMaOeZfH304eCnSQJvt8"; at-main=Atza|IwEBIIHiQBP2ekN9tCj75ZsZmZCoNsXKGnikQhSe6I2OvVa52biMT5vwMeqiyI4V918rcOWRM9biQUC2TX8CW0YiMIMU5zQrvjE8LkAcbhLYBS6Vt3sdwS1ST_k2XUiDCQIRtoRFQqVPee_8aAXk7vy1BBC0ixLj1kud2tuluFytgRHEy_bLh7aU3yfksl9oolxqsODyrAanUfOsFGq-oDQqVZgJgFXFnshd3cLZ-HRK2eCyqw; sess-at-main="N3rC9LAQuFREfxJTMvmIc3Ay3f8OlEX2BZ1EvY9skv4="; sst-main=Sst1|PQF0ropFT7lc4exFGM5BATs2CeFOmpuMPXdAAM6jLx6CSZnsbg3a056aiqsltwQspzdog0bwEwnZ8BR59tLVUZegpd-HP348mse0YM6kTsslDvpq0pp5x9MgCKwPCpYrdpybPtTCO-ZSeEWpYZVzs3Ygq-aOnGw96iVyo6mc6nAZOM9J4PEMAmlm1boNjc17WyPV3hmkXv9lNsGKBdmVInO8isIo3iOcKat_9r5phf-PwTmJ9eQnBAX2a8aLCcwP8GZYu-LrCy29yf2zw-H2Gw3pxGjTCnigrahN_NVvCq2BMSs',
          'Referer' =>  'https => //www.amazon.com/',
          'Sec-Fetch-Dest' =>  'empty',
          'Sec-Fetch-Mode' =>  'no-cors',
          'Sec-Fetch-Site' =>  'same-site',
          'User-Agent' =>  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'sec-ch-ua' =>  '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
          'sec-ch-ua-mobile' =>  '?0',
          'sec-ch-ua-platform' =>  'macOS'
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