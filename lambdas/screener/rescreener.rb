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

class Rescreener
  class << self
    def handler(event:, context:)
      region = ENV.fetch("AWS_REGION", "us-east-1")

      sqs = Aws::SQS::Client.new(region: region)

      source_name = "dumpsterfire-print.fifo"
      target_name = "dumpsterfire-screener.fifo"

      #source_url = sqs.get_queue_url(queue_name: source_name).queue_url
      source_url = event["queue"]
      source = Aws::SQS::Queue.new(source_url)
      source_poller = Aws::SQS::QueuePoller.new(source_url)

      target_resp = sqs.get_queue_url(queue_name: target_name)
      target = Aws::SQS::Queue.new(target_resp.queue_url)

      messages_to_pull = source.attributes["ApproximateNumberOfMessages"].to_i
      max_requests = (messages_to_pull/10.0).ceil

      puts "Pulling #{max_requests*10} off #{source_name} in #{max_requests} batches"

      source_poller.before_request do |stats|
        throw :stop_polling if stats.received_message_count >= messages_to_pull
      end

      options = {
        max_number_of_messages: 10,
        wait_time_seconds: 1,
        idle_timeout: 10
      }

      stats = source_poller.poll(options) do |messages|
        timestamp = (Time.now.to_f * 1000).to_i.to_s
        begin
          new_msgs = messages.inject([]) do |arry, msg|
            arry << {
              id: msg.message_id,
              message_body: msg.body,
              message_deduplication_id: msg.message_id,
              message_group_id: timestamp
            }
          end
          results = target.send_messages({entries: new_msgs})
          puts results["failed"] unless results["failed"].empty?
        rescue StandardError => e
          puts e
          throw :skip_delete
        end
      end

      puts "requests: #{stats.request_count}"
      puts "messages: #{stats.received_message_count}"

      return stats.received_message_count
    end
  end
end


# UNUSED
class OldRescreener
  class << self
    def handler(event:, context:)
      region = ENV.fetch("AWS_REGION", "us-east-1")
      #ENV['AWS_PROFILE'] = "lambda"

      sqs = Aws::SQS::Client.new(region: region)
      source_name = "dumpsterfire-print.fifo"
      target_name = "dumpsterfire-screener.fifo"

      source_url = sqs.get_queue_url(queue_name: source_name).queue_url
      source = Aws::SQS::Queue.new(source_url)
      source_poller = Aws::SQS::QueuePoller.new(source_url)

      target_resp = sqs.get_queue_url(queue_name: target_name)
      target = Aws::SQS::Queue.new(target_resp.queue_url)

      messages_to_pull = source.attributes["ApproximateNumberOfMessages"].to_i
      max_requests = (messages_to_pull/10.0).ceil

      puts "Pulling #{messages_to_pull} off #{source_name} in #{max_requests} batches"
      received_message_count = 0
      failed_message_count = 0
      num_requests = 0
      begin
        while(received_message_count <= messages_to_pull)
          raise "TooManyRequests" if num_requests > max_requests
          raise "Stalled" if (num_requests > 1 && received_message_count == 0)
          num_requests += 1
          batch = source.receive_messages({max_number_of_messages: 10, wait_time_seconds: 5})
          timestamp = (Time.now.to_f * 1000).to_i.to_s
          if batch.size > 0
            new_msgs = batch.inject([]) do |arry, msg|
              arry << {
                id: msg.message_id,
                message_body: msg.body,
                message_deduplication_id: msg.message_id,
                message_group_id: timestamp
              }
            end

            results = target.send_messages({entries: new_msgs})

            received_message_count += results.successful.count
            failed_message_count += results.failed.count
            puts results.failed unless results.failed.empty?

            # Filter batch; only delete messages that were successful

            failure_ids = results.failed.map{|f| f.id }.compact
            puts batch_delete_successful!(batch, failure_ids)
          end
        end
      rescue => e
        puts e
        puts e.backtrace
      end
      puts "messages: #{received_message_count}"

      return received_message_count
    end

    def batch_delete_successful!(batch, failure_ids)
      entries = []
      batch.each do |b|
        entries << b unless failure_ids.include?(b.message_id)
      end
      return Aws::SQS::Message::Collection.new([entries], size: entries.count).batch_delete!
    end
  end
end
