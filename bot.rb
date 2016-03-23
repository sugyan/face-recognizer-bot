require 'twitter'

client = Twitter::Streaming::Client.new do |config|
  config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
  config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
  config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
  config.access_token_secret = ENV['TWITTER_ACCESS_SECRET']
end

client.user do |object|
  case object
  when Twitter::Tweet
    puts 'a tweet!'
  when Twitter::Streaming::Event
    puts 'a event!'
  when Twitter::Streaming::StallWarning
    warn 'Falling behind!'
  end
end
