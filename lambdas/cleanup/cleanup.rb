# frozen_string_literal: true

libx = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(libx) unless $LOAD_PATH.include?(libx)

require 'rubygems'
require 'bundler/setup'
require 'date'
require 'json'
require 'logger'
require 'aws-sdk-s3'
require 'aws-sdk-sqs'

class Cleanup
  FLOW = {
    "inbound": "screened",
    "screened": "print",
    "print": "completed"
  }

  STATE = {
    inbound: "screening",
    screened: "rendering",
    print: "printing",
    complete: "completed"
  }

  class << self
    def handler(event:, context:)
      logger = Logger.new($stdout)
      client = Aws::S3::Client.new(region: ENV['AWS_REGION'])
      s3 = Aws::S3::Resource.new(client: client)
      sqs = Aws::SQS::Client.new(region: ENV['AWS_REGION'])
      resp = sqs.get_queue_url(queue_name: "dumpsterfire-complete-reply.fifo")
      queue = Aws::SQS::Queue.new(resp.queue_url)

      logger.info event.to_json
      return unless event['Records']

      event['Records'].each do |event_record|
        job = JSON.parse event_record['body']

        logger.info "Processing #{job['id']}"
        source_key = job['key']
        bucket = job['bucket']
        target_key = "completed/#{job['id']}"

        source = s3.bucket(bucket).object(source_key)
        target = s3.bucket(bucket).object(target_key)

        source.delete
        job['key'] = target_key
        target.put(body: job.to_json)
        # Drop the job into the complete-reply queue for the final mailing
        queue.send_message({
          message_body: job.to_json,
          message_deduplication_id: job["id"],
          message_group_id: "complete"
        })
        logger.info "Finished #{job['id']}"
      end
    end
  end
end
