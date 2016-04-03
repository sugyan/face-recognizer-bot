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
      @logger.info(reply)
      medias = reply[:images].map do |image|
        tmp = Tempfile.new(['', '.jpg'])
        image.write(tmp.path)
        image.destroy!
        @rest.upload(tmp)
      end
      @logger.info(@rest.update(reply[:text], in_reply_to_status: tweet, media_ids: medias.join(',')))
      img.destroy!
    rescue StandardError => e
      @logger.warn(e)
    end
  end

  def create_reply(screen_name, img, faces)
    return { text: "@#{screen_name} 顔が検出されませんでした\u{1f60e}", images: [] } if faces.empty?
    recognized = faces.select { |face| face['recognize'].first['label']['id'] }
    result = recognized.empty? ? "しかしどれも識別できませんでした\u{1f61e}" : format("うち%d件を識別しました\u{1f600}", recognized.size)
    texts = [format("@#{screen_name} %d件の顔を検出\u{1f610} %s", faces.size, result)]
    recognized.sort! { |a, b| b['recognize'].first['value'] <=> a['recognize'].first['value'] }
    images = []
    recognized.each.with_index do |face, i|
      # text
      label = face['recognize'].first['label']
      value = face['recognize'].first['value']
      line = format('%d: %s (%s) [%.2f]', i + 1, label['name'], label['description'].split(/\n/).first, value * 100.0)
      break if texts.join("\n").size + line.size + 1 >= 140
      texts << line
      # image
      xs = face['bounding'].map { |v| v['x'] }
      ys = face['bounding'].map { |v| v['y'] }
      size = [xs.max - xs.min, ys.max - ys.min].max
      rvg = Magick::RVG.new(size, size) do |canvas|
        canvas
          .image(img)
          .translate(size * 0.5, size * 0.5)
          .rotate(-face['angle']['roll'])
          .translate(-(xs.min + xs.max) * 0.5, -(ys.min + ys.max) * 0.5)
      end
      images << rvg.draw
    end
    { text: texts.join("\n"), images: images }
  end
end
