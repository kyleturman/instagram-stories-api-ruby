require 'rubygems'
require 'bundler/setup'
require 'curb'
require 'json'
require 'yaml'

class InstagramStoriesAPI
  LOGINFILE_PATH     = File.join(__dir__, "config/login.yml")
  SETTINGSFILE_PATH  = File.join(__dir__, "config/settings.yml")
  DEVICESFILE_PATH   = File.join(__dir__, "data/devices.csv")
  COOKIEFILE_PATH    = File.join(__dir__, "tmp/cookies.dat")

  SETTINGS = YAML.load_file(SETTINGSFILE_PATH)

  # Initialization
  # ----------------------------------------------------------

  def initialize
    login = YAML.load_file(LOGINFILE_PATH)
    @username = login["username"]
    @password = login["password"]

    @cookies = parse_cookiefile()
    @user_agent = generate_user_agent()
    @uuid = generate_uuid(true)
    @device_id = generate_device_id(Digest::MD5.hexdigest(@username + @password))
  end


  # Methods
  # ----------------------------------------------------------
  def get_user_stories user_id = nil
    check_cookies()
    user_id = @cookies["ds_user_id"]["value"] if !user_id

    response = request("feed/user/#{user_id}/reel_media/")
    response["response"]
  end

  def get_stories
    check_cookies()
    response = request("feed/reels_tray/")
    response["response"]
  end


  private

    # Logging in
    # ----------------------------------------------------------
    def login
      data = JSON.generate({
        "phone_id" =>   generate_uuid(true),
        "username" =>   @username,
        "password" =>   @password,
        "guid" =>       @uuid,
        "device_id" =>  @device_id,
        "login_attempt_count" => 0
      })

      body = generate_signature(data)
      request("accounts/login/", body, false)
    end


    # HTTP requests
    # ----------------------------------------------------------
    def request(url, data = nil, use_existing_cookies = true)
      http = Curl::Easy.new(SETTINGS["api_url"] + url)

      http.headers["User-Agent"] = @user_agent
      http.headers["x-ig-capabilities"] = "3w=="
      http.headers["Accept"] = "*/*"
      http.headers["Connection"] = "close"
      http.headers["Cookie2"] = "$Version=1"
      http.headers["Accept-Language"] = "en-US"
      http.headers["Content-type"] = "application/x-www-form-urlencoded; charset=UTF-8"

      http.verbose = false
      http.follow_location = true
      http.enable_cookies = true

      if use_existing_cookies
        http.cookiefile = COOKIEFILE_PATH
      else
        http.cookiejar = COOKIEFILE_PATH
      end

      if data
          http.headers["Content-type"] = "application/x-www-form-urlencoded; charset=UTF-8"
          http.send("post", data)
      else
          http.headers["Content-type"] = "application/json; charset=UTF-8"
          http.send("get")
      end

      http_headers = http.header_str
      parsed_response = JSON.parse(http.body) rescue http.body

      http.close

      if !use_existing_cookies
        @cookies = parse_cookiefile
      end

      {
        "headers" => http_headers,
        "response" => parsed_response
      }
    end


    # Cookies
    # ----------------------------------------------------------
    def check_cookies
      if @cookies.length == 0
        login()
      elsif @cookies["ds_user_id"]["expiration"] <= Time.now.utc
        login()
      end
    end

    def parse_cookiefile
      cookies = {}
      cookiefile = File.open(COOKIEFILE_PATH,"a+")
      cookiefile.readlines.each do |line|
        cookie = line.strip.split("\t") if line.length > 1 && line[0] != "#"
        if cookie && cookie.length
          cookies[cookie[5]] = {
            "domain" =>     (cookie[0] rescue ""),
            "flag" =>       (cookie[1] rescue ""),
            "path" =>       (cookie[2] rescue ""),
            "secure" =>     (cookie[3] rescue ""),
            "expiration" => (Time.at(cookie[4].to_f) rescue Time.now + 1.day).utc,
            "value" =>      (cookie[6] rescue "")
          }
        end
      end
      cookies
    end

    # Signature
    # ----------------------------------------------------------
    def generate_signature(data)
      hash = OpenSSL::HMAC.hexdigest("sha256", SETTINGS["ig_sig_key"], data)
      return "ig_sig_key_version=#{SETTINGS["sig_key_version"]}&signed_body=#{hash}." + URI::encode(data)
    end


    # String generators
    # ----------------------------------------------------------
    def generate_device_id(seed)
      volatile_seed = File.mtime(__FILE__).to_s;
      "android-" + Digest::MD5.hexdigest(seed+volatile_seed)[0..16]
    end

    def generate_user_agent
      devices = File.foreach(DEVICESFILE_PATH).map(&:to_s)
      device = devices.sample.strip.split(";")

      sprintf("Instagram %s Android (%s/%s; 320dpi; 720x1280; %s; %s; %s; qcom; en_US)",
        SETTINGS["version"],
        SETTINGS["android_version"],
        SETTINGS["android_release"],
        device[0],
        device[1],
        device[2]
      )
    end

    def generate_uuid(type)
      uuid = sprintf("%04x%04x-%04x-%04x-%04x-%04x%04x%04x",
        Random.rand(0..0xffff),
        Random.rand(0..0xffff),
        Random.rand(0..0xffff),
        Random.rand(0..0x0fff) | 0x4000,
        Random.rand(0..0x3fff) | 0x8000,
        Random.rand(0..0xffff),
        Random.rand(0..0xffff),
        Random.rand(0..0xffff)
      )

      type ? uuid : uuid.gsub("-","")
    end
end
