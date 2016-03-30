require 'twitter'
require 'logger'

logger = Logger.new(STDOUT)

client = Twitter::Streaming::Client.new do |config|
  config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
  config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
  config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
  config.access_token_secret = ENV['TWITTER_ACCESS_SECRET']
end

client.user do |object|
  logger.info('start')
  case object
  when Twitter::Tweet
    logger.info(format('tweet: %s', object.id))
  when Twitter::Streaming::Event
    logger.info(format('event: %s', object))
  when Twitter::Streaming::StallWarning
    logger.warn('Falling behind!')
  end
end
