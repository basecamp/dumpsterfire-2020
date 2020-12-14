# frozen_string_literal: true

#
# This is not used; incineration happens in the screener. I wasn't sure how fast that would be.
#


libx = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(libx) unless $LOAD_PATH.include?(libx)

require 'rubygems'
require 'bundler/setup'
require 'date'
require 'json'
require 'base64'
require 'logger'
require 'aws-sdk-s3'
require 'aws-sdk-sqs'

class Incinerator
  class << self
    def handler(event:, context:)
      client = Aws::S3::Client.new(region: ENV['AWS_REGION'])
      s3 = Aws::S3::Resource.new(client: client)

      # Loop thru events
      STDOUT.puts event.to_json
      return unless event['Records']

      event['Records'].each do |event_record|
        begin
          full_key = event_record['body']
          bucket_name, state, leaf_key = full_key.split("/")
          key = [state, leaf_key].join("/")

          object = s3.bucket(bucket_name).object(key)

          object.delete
        rescue StandardError => e
          STDOUT.puts e.inspect
        end
      end
      STDOUT.puts "Deleted #{event['Records'].count}"

    end

  end
end
