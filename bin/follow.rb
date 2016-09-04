#!/usr/bin/env ruby
require 'twitter'
require 'httpclient'
require 'logger'

logger = Logger.new(STDOUT)

rest = Twitter::REST::Client.new do |config|
  config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
  config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
  config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
  config.access_token_secret = ENV['TWITTER_ACCESS_SECRET']
end

uri = URI(ENV['LABELS_ENDPOINT_URL'])
screen_names = JSON.parse(HTTPClient.new.get(uri).content)['labels'].each_value.map { |v| v['twitter'] }
screen_names.shuffle.each_slice(100) do |names|
  rest.friendships(screen_name: names.join(',')).each do |user|
    logger.info(format('%s (%s): %s', user.name, user.screen_name, user.connections))
    unless user.connections.include?('following')
      logger.info(rest.follow(user))
      sleep 1
    end
  end
end
