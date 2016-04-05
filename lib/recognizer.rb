# coding: utf-8
require 'base64'
require 'httpclient'
require 'json'
require 'logger'
require 'rmagick'
require 'rvg/rvg'
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
    @configuration = @rest.configuration
    @user = @rest.verify_credentials
    @logger.info("user @#{@user.screen_name}")
    @streaming.user do |object|
      case object
      when Twitter::Tweet
        @logger.info("tweet: #{object.uri}")
        process_reply(object)
      when Twitter::Streaming::Event
        @logger.info("event: [#{object.name}] #{object.source} - #{object.target}")
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
    unless tweet.media?
      @logger.info('no media.')
      return
    end

    begin
      url = tweet.media.first.media_url
      @logger.info("media: #{url}")
      img = Magick::Image.read(url).first
      b64 = Base64.strict_encode64(img.to_blob { self.format = 'JPG' })
      body = { 'image' => 'data:image/jpeg;base64,' + b64 }
      results = JSON.parse(HTTPClient.new.post(recognizer_api, body).content)
      @logger.info(results['message'])
      reply = create_reply(tweet.user.screen_name, img, results['faces'])
      img.destroy!
      @logger.info(reply)
      medias = reply[:images].map do |image|
        tmp = Tempfile.new(['', '.jpg'])
        image.write(tmp.path)
        image.destroy!
        @rest.upload(tmp)
      end
      options = { in_reply_to_status: tweet }
      options[:media_ids] = medias.join(',') unless medias.empty?
      updated = @rest.update(reply[:text], options)
      @logger.info("update: #{updated.uri}")
    rescue StandardError => e
      @logger.warn(e)
    end
  end

  def create_reply(screen_name, img, faces)
    return { text: "@#{screen_name} 顔を検出できませんでした\u{1f61e}", images: [] } if faces.empty?
    recognized = faces.select { |face| face['recognize'].first['label']['id'] }
    return { text: "@#{screen_name} #{faces.size}件の顔を検出しましたが、1つも識別できませんでした\u{1f61e}", images: [] } if recognized.empty?

    texts = ["@#{screen_name} #{faces.size}件中 #{recognized.size}件の顔を識別しました\u{1f600}"]
    recognized.sort! { |a, b| b['recognize'].first['value'] <=> a['recognize'].first['value'] }
    images = []
    recognized.slice(0, 4).each.with_index do |face, i|
      # text
      label = face['recognize'].first['label']
      value = face['recognize'].first['value']
      name = label['name']
      unless label['description'].empty?
        name += " (#{label['description'].split(/\n/).first})"
      end
      line = format("#{i + 1}: #{name} [%.2f]", value * 100.0)
      if texts.join("\n").size + line.size + 1 >= 140 - @configuration.short_url_length - 2
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
    rvg = Magick::RVG.new(x_size * 1.2, y_size * 1.2) do |canvas|
      canvas
        .image(img)
        .translate(x_size * 0.6, y_size * 0.6)
        .rotate(-face['angle']['roll'])
        .translate(-(xs.min + xs.max) * 0.5, -(ys.min + ys.max) * 0.5)
    end
    rvg.draw
  end
end
