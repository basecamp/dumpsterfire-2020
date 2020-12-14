# frozen_string_literal: true

libx = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(libx) unless $LOAD_PATH.include?(libx)

require 'rubygems'
require 'bundler/setup'
require 'date'
require 'json'
require 'aws-sdk-s3'
require 'aws-sdk-sqs'
require 'dumpster_mail'

class Processor
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

  CLOUDFRONT = "dumpsterfire-cloudfront"

  class << self
    def handler(event:, context:)
      client = Aws::S3::Client.new(region: ENV['AWS_REGION'])
      s3 = Aws::S3::Resource.new(client: client)

      # Uncomment puts for debug output
      # puts event.to_json
      return unless event['Records']

      event['Records'].each do |event_record|
        s3_message = JSON.parse event_record['Sns']['Message']

        return "No Files to process" unless s3_message['Records']

        s3_message['Records'].each do |record|
          bucket_name = record['s3']['bucket']['name']
          key = record['s3']['object']['key']

          # Assumes one-level deep action/key path
          state,leaf_key = parse_key(key)


          # puts "Current: #{state}, Action: #{current_step(state)}"
          # Early Return if we've completed this
          return if ["error", "print"].include?(state)

          case state
          # Failsafe
          when "print"
            return
          when "inbound"
            screen(s3, bucket_name, key)
          when "screened"
            render(s3, bucket_name, key)
          when "completed"
            completed(s3, bucket_name, key)
          else
            copy_process(s3, bucket_name, key)
          end
        end
      end
    end

    def parse_key(key)
      key.split("/")
    end

    def current_step(state)
      Processor::STATE.fetch(state.to_sym, "error")
    end

    def next_step(state)
      Processor::FLOW.fetch(state.to_sym, "error")
    end

    # Basic copy step. Doesn't do anything, just copies to the next step
    def copy_process(s3, bucket_name, key)
      state,leaf_key = parse_key(key)
      object = s3.bucket(bucket_name).object(key)

      # Defensive; in case the object has already been processed.
      if object.exists?
        target = next_step(state) + "/" + leaf_key
        puts "#{current_step(state).capitalize} complete; moving to #{target}"
        response = object.move_to(bucket: bucket_name, key: target)
      else
        puts "Duplicate Event (#{key} already processed); Exiting"
      end
    end

    # Basic screener; just checks filesize right now
    def screen(s3, bucket_name, key)
      state,leaf_key = parse_key(key)
      object = s3.bucket(bucket_name).object(key)
      valid = true

      # Defensive; in case the object has already been processed.
      if object.exists?
        target = next_step(state) + "/" + leaf_key

        # Check to see if we're obnoxiously large
        if object.content_length > 5242880 # 5MiB
          puts "Too Big #{object.content_length} > 5MB"
          valid = false
        end

        if valid
          puts "#{current_step(state).capitalize} complete; moving to #{target}"
        else
          target = next_step("error") + "/" + leaf_key
        end

        response = object.move_to(bucket: bucket_name, key: target)
      else
        puts "Duplicate Event (#{key} already processed); Exiting"
      end
    end

    # Actually render something out, txt, pdf, whatever.
    def render(s3, bucket_name, key)
      require 'mail'
      sqs = Aws::SQS::Client.new(region: ENV['AWS_REGION'])
      resp = sqs.get_queue_url(queue_name: "dumpsterfire-screener.fifo")
      queue = Aws::SQS::Queue.new(resp.queue_url)

      resp = sqs.get_queue_url(queue_name: "dumpsterfire-reply.fifo")
      reply_queue = Aws::SQS::Queue.new(resp.queue_url)

      state,leaf_key = parse_key(key)
      object = s3.bucket(bucket_name).object(key)
      valid = true

      # Defensive; in case the object has already been processed.
      if object.exists?
        raw_email = object.get.body.read

        begin
          dm = DumpsterMail.new raw_email
          valid = dm.valid?
        rescue StandardError => e
          valid = false
        end

        if valid
          target = next_step(state) + "/" + leaf_key
          new_object = s3.bucket(object.bucket_name).object(target)
          data = {
            id: leaf_key,
            email: dm.from,
            is_hey: dm.is_hey?,
            subject: dm.subject,
            content_type: dm.content_type,
            content: dm.render
          }


          puts "#{current_step(state).capitalize} complete; moving to #{target}"

          if resp = new_object.put({body: data.to_json, content_type: "application/json"})
            object.delete
            # puts "#{target} uploaded."
            sqs_data = {
              key: new_object.key,
              bucket: new_object.bucket_name
            }
            queue.send_message({
              message_body: sqs_data.to_json,
              message_deduplication_id: leaf_key,
              message_group_id: (Time.now.to_f * 1000).to_i.to_s
            })

            position = (queue.attributes["ApproximateNumberOfMessages"].to_i) + 1

            # puts "Message Queued in SQS."
            reply_queue.send_message({
              message_body: { from: dm.from, position: position, key: leaf_key}.to_json,
              message_deduplication_id: leaf_key,
              message_group_id: "reply"
            })
          end

        else
          puts "Invalid email"
          target = next_step("error") + "/" + leaf_key
          response = object.move_to(bucket: bucket_name, key: target)
        end
      else
        puts "Duplicate Event (#{key} already processed); Exiting"
      end
    end

    # Handle completed objects
    def completed(s3, bucket_name, key)
      puts "Completed; Updating Stats"
      stats_file = "stats.json"
      object = s3.bucket(Processor::CLOUDFRONT).object(stats_file)
      current = {}
      if object.exists?
        current = JSON.parse(object.get.body.read)
        current["counter"] += 1 || 1
      else
        current["counter"] = 1
      end
      puts "#{current["counter"]} processed so far!"
      object.put({body: current.to_json, content_type: "application/json"})
    end
  end
end
