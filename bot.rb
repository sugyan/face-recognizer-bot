require 'base64'
require 'twitter'
require 'httpclient'
require 'json'
require 'logger'
require 'rmagick'

logger = Logger.new(STDOUT)

rest = Twitter::REST::Client.new do |config|
  config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
  config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
  config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
  config.access_token_secret = ENV['TWITTER_ACCESS_SECRET']
end

streaming = Twitter::Streaming::Client.new do |config|
  config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
  config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
  config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
  config.access_token_secret = ENV['TWITTER_ACCESS_SECRET']
end

user = rest.verify_credentials
logger.info("user @#{user.screen_name}")

streaming.user do |object|
  case object
  when Twitter::Tweet
    logger.info("tweet: #{object.uri}")

    unless object.reply? && object.in_reply_to_user_id == user.id
      logger.info('not reply for this user.')
      next
    end
    unless object.media?
      logger.info('no media.')
      next
    end

    begin
      url = object.media.first.media_url
      logger.info("media: #{url}")
      img = Magick::Image.read(url).first
      b64 = Base64.strict_encode64(img.to_blob { self.format = 'JPG' })
      img.destroy!
      body = { 'image' => 'data:image/jpeg;base64,' + b64 }
      res = HTTPClient.new.post(ENV['RECOGNIZER_ENDPOINT_URL'], body)
      logger.info(res.content)
    rescue StandardError => e
      logger.warn(e)
    end
  when Twitter::Streaming::Event
    logger.info("event: #{object}")
  when Twitter::Streaming::FriendList
    logger.info("friend list: #{object}")
  when Twitter::Streaming::StallWarning
    logger.warn('Falling behind!')
  end
end
