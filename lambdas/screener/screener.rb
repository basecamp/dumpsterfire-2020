# frozen_string_literal: true

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

class Screener
  class << self
    def handler(event:, context:)
      client = Aws::S3::Client.new(region: ENV['AWS_REGION'])
      s3 = Aws::S3::Resource.new(client: client)

      rules_version = 1

      blocked_senders = %w();
      blocked_domains = %w();
      blocked_content = [/baz bat/i];

      # Update our rules from the bucket
      begin
        rules = JSON.parse s3.bucket("dumpsterfire-rules").object("rules.json").get.body.read
        # STDOUT.puts rules.inspect

        blocked_senders = rules["senders"] || []
        blocked_domains = rules["domains"] || []
        blocked_content = rules["content"].map{ |r| (r.start_with?("/") ? Regexp.new(r.delete("/"), true) : r) }
        blocked_prefixes = rules["prefixes"] || []
        special_codes = rules["special_codes"] || []
        rules_version = rules["version"]
        STDOUT.puts "Loaded #{blocked_senders.count + blocked_domains.count + blocked_content.count + blocked_prefixes.count} rules"
      rescue StandardError => e
        STDOUT.puts e.inspect
        STDOUT.puts "Loaded 0 rules"
      end

      # Loop thru events
      # STDOUT.puts event.to_json
      return unless event['Records']

      event['Records'].each do |event_record|
        begin
          blocked = false
          blob = JSON.parse(event_record['body'])
          bucket_name = blob["bucket"]
          key = blob["key"]
          state, leaf_key = parse_key(key)

          object = s3.bucket(bucket_name).object(key)
          job = JSON.parse object.get.body.read
          from = job["email"]
          localPart,domain = from.split("@")

          # STDOUT.puts job.inspect

          #puts "Scanned By: #{job.fetch("scanned_by", 0).to_i}; rules_version: #{rules_version}"
          # Short circuit for jobs scanned by this ruleset already
          if job.fetch("scanned_by", 0).to_i >= rules_version
            keep(bucket_name, state, leaf_key, rules_version)
            next
          end

          if blocked_senders.include?(from) || blocked_domains.include?(domain) || blocked_prefixes.include?(localPart)
            puts "Sender/Domain In Blocklist"
            blocked = true
          end

          if blocked != true && job["content_type"].include?("text/plain")
            content = Base64.decode64(job["content"])
            regex_list = Regexp.union(blocked_content)
            blocked = content.match?(regex_list) ? true : false
            puts "Content Blocked" if blocked
          end

          options = {
            bucket_name: bucket_name,
            state: state,
            leaf_key: leaf_key,
            rules_version: rules_version,
            is_hey: job['is_hey'],
            is_special: special_codes.include?(job['subject'])
          }
          # If this is blocked; trash it
          blocked ? incinerate(options) : keep(options)
        rescue StandardError => e
          STDOUT.puts e.inspect
        end
      end
    end

    def parse_key(key)
      key.split("/")
    end

    def incinerate(options = {})
      bucket_name = options[:bucket_name]
      leaf_key = options[:leaf_key]
      state = options[:state]
      STDOUT.puts "Incinerating #{leaf_key}"
      client = Aws::S3::Client.new(region: ENV['AWS_REGION'])
      s3 = Aws::S3::Resource.new(client: client)
      object = s3.bucket(bucket_name).object([state, leaf_key].join("/"))
      object.delete
    end

    def keep(options = {})

      bucket_name = options[:bucket_name]
      leaf_key = options[:leaf_key]
      state = options[:state]
      version = options[:version]
      is_special = options[:is_special]
      is_hey = options[:is_hey]
      #raise StandardError.new "ArgumentError" unless bucket_name && leaf_key && version

      STDOUT.puts "Keeping #{leaf_key}"
      sqs = Aws::SQS::Client.new(region: ENV['AWS_REGION'])
      resp = sqs.get_queue_url(queue_name: "dumpsterfire-print.fifo")
      normal_queue = Aws::SQS::Queue.new(resp.queue_url)
      vip_resp = sqs.get_queue_url(queue_name: "dumpsterfire-print-vip.fifo")
      vip_queue = Aws::SQS::Queue.new(vip_resp.queue_url)
      alpha_resp = sqs.get_queue_url(queue_name: "dumpsterfire-print-alpha.fifo")
      alpha_queue = Aws::SQS::Queue.new(alpha_resp.queue_url)

      # Show some love to the VIP's!
      if is_special
        STDOUT.puts "ALPHA: #{leaf_key}"
        queue = alpha_queue
      elsif is_hey
        queue = vip_queue
      else
        queue = normal_queue
      end

      sqs_data = {
        key: [state, leaf_key].join("/"),
        bucket: bucket_name,
        scanned_by: version
      }

      resp = queue.send_message({
        message_body: sqs_data.to_json,
        message_deduplication_id: "#{leaf_key}-#{Time.now.to_i}",
        message_group_id: (Time.now.to_f * 1000).to_i.to_s
      })
    end

  end
end
