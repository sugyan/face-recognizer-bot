require 'base64'
require 'httpclient'
require 'json'
require 'logger'
require 'rmagick'
require 'twitter'

# recognizer bot class
class Recognizer
  attr_accessor :consumer_key, :consumer_secret, :access_token, :access_token_secret, :recognizer_api

  def initialize
    @logger = Logger.new(STDOUT)
    yield(self) if block_given?
    @rest = Twitter::REST::Client.new do |config|
      config.consumer_key        = consumer_key
      config.consumer_secret     = consumer_secret
      config.access_token        = access_token
      config.access_token_secret = access_token_secret
    end
    @streaming = Twitter::Streaming::Client.new do |config|
      config.consumer_key        = consumer_key
      config.consumer_secret     = consumer_secret
      config.access_token        = access_token
      config.access_token_secret = access_token_secret
    end
  end

  def run
    @user = @rest.verify_credentials
    @logger.info("user @#{@user.screen_name}")
    @streaming.user do |object|
      case object
      when Twitter::Tweet
        @logger.info("tweet: #{object.uri}")
        process_reply(object)
      when Twitter::Streaming::Event
        @logger.info("event: #{object}")
      when Twitter::Streaming::FriendList
        @logger.info("friend list: #{object}")
      when Twitter::Streaming::StallWarning
        @logger.warn('Falling behind!')
      end
    end
  end

  private

  def process_reply(tweet)
    unless tweet.reply? && tweet.in_reply_to_user_id == @user.id
      @logger.info('not reply for this user.')
      return
    end
    unless tweet.media?
      @logger.info('no media.')
      return
    end

    begin
      url = tweet.media.first.media_url
      @logger.info("media: #{url}")
      img = Magick::Image.read(url).first
      b64 = Base64.strict_encode64(img.to_blob { self.format = 'JPG' })
      img.destroy!
      body = { 'image' => 'data:image/jpeg;base64,' + b64 }
      results = JSON.parse(HTTPClient.new.post(recognizer_api, body).content)
      @logger.info(results['message'])
    rescue StandardError => e
      @logger.warn(e)
    end
  end
end
