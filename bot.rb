require 'twitter'
require 'logger'

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
logger.info(format('user @%s', user.screen_name))

streaming.user do |object|
  case object
  when Twitter::Tweet
    logger.info(format('tweet: %s', object.uri))

    unless object.reply? && object.in_reply_to_user_id == user.id
      logger.info('not reply to me.')
      next
    end
    unless object.media?
      logger.info('no media.')
      next
    end

    logger.info(object.media.first)
  when Twitter::Streaming::Event
    logger.info(format('event: %s', object))
  when Twitter::Streaming::FriendList
    logger.info(format('friend list: %s', object))
  when Twitter::Streaming::StallWarning
    logger.warn('Falling behind!')
  end
end
