# coding: utf-8
# frozen_string_literal: true
require 'base64'
require 'httpclient'
require 'json'
require 'logger'
require 'mini_magick'
require 'tempfile'
require 'twitter'

# recognizer bot class
class Recognizer
  attr_accessor :consumer_key, :consumer_secret, :access_token, :access_token_secret, :recognizer_api

  def initialize
    STDOUT.sync = true
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
        process_reply(object)
      when Twitter::Streaming::Event
        @logger.info("event: [#{object.name}] @#{object.source.screen_name}")
      when Twitter::Streaming::FriendList
        @logger.info("friend list: #{object}")
      when Twitter::Streaming::StallWarning
        @logger.warn('Falling behind!')
      end
    end
  end

  private

  def process_reply(tweet)
    return unless tweet.reply? && tweet.in_reply_to_user_id == @user.id
    @logger.info("tweet: #{tweet.uri}")
    unless tweet.media?
      @logger.info('no media.')
      return
    end

    begin
      url = tweet.media.first.media_url
      @logger.info("media: #{url}")
      img = MiniMagick::Image.open(url)
      body = { 'image' => "data:image/jpeg;base64,#{Base64.strict_encode64(img.to_blob)}" }
      results = JSON.parse(HTTPClient.new.post(recognizer_api, body).content)
      @logger.info(results['message'])
      reply = create_reply(tweet.user.screen_name, img, results['faces'])
      @logger.info(reply)
      medias = reply[:images].map do |image|
        @rest.upload(image.tempfile.open)
      end
      options = { in_reply_to_status: tweet }
      options[:media_ids] = medias.join(',') unless medias.empty?
      updated = @rest.update(reply[:text], options)
      @logger.info("replied: #{updated.uri}")
    rescue StandardError => e
      @logger.warn(e)
    end
  end

  def create_reply(screen_name, img, faces)
    if faces.empty?
      return {
        text: "@#{screen_name} 顔を検出できませんでした\u{1f61e}",
        images: []
      }
    end
    recognized = faces.select do |face|
      top = face['recognize'].first
      top['label']['id'] && top['value'] > 0.5
    end
    if recognized.empty?
      return {
        text: "@#{screen_name} #{faces.size}件の顔を検出しましたが、識別対象の人物ではなさそうです\u{1f61e}",
        images: []
      }
    end

    message = "#{recognized.size}件の顔を識別しました\u{1f600}"
    message = "#{faces.size}件中 " + message if faces.size > recognized.size

    recognized_result("@#{screen_name} #{message}", recognized, img)
  end

  def recognized_result(message, recognized, img)
    texts = [message]
    recognized.sort! { |a, b| b['recognize'].first['value'] <=> a['recognize'].first['value'] }
    images = []
    prev = nil
    recognized.slice(0, 4).each.with_index do |face, i|
      # text
      value = face['recognize'].first['value']
      desc = face['recognize'].first['label']['description'].split(/\r?\n/).first
      name = face['recognize'].first['label']['name']
      name += " (#{desc == prev ? '同上' : desc})" if desc
      prev = desc
      line = format("#{i + 1}: %s [%.2f]", name, value * 100.0)
      if texts.join("\n").size + line.size + 1 >= 140 - 2
        texts << '他'
        break
      end
      texts << line
      # image
      images << crop_face(img, face)
    end
    { text: texts.join("\n"), images: images }
  end

  def crop_face(img, face)
    xs = face['bounding'].map { |v| v['x'] }
    ys = face['bounding'].map { |v| v['y'] }
    x_size = xs.max - xs.min
    y_size = ys.max - ys.min
    srt = [
      "#{(xs.min + xs.max) * 0.5},#{(ys.min + ys.max) * 0.5}",
      1.0,
      -face['angle']['roll'],
      "#{x_size * 0.6},#{y_size * 0.6}"
    ].join(' ')
    MiniMagick::Image.open(img.path).mogrify do |convert|
      convert.background('black')
      convert.virtual_pixel('background')
      convert.distort(:SRT, srt)
      convert.crop("#{x_size * 1.2}x#{y_size * 1.2}+0+0")
    end
  end
end
