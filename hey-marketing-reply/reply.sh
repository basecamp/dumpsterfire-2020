#!/usr/bin/env bash
set -euo pipefail

PATH=/path/to/aws-sdk/bin:$PATH

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

NUM_MESSAGES=10
FROM="dumpsterfire@hey.com"
QUEUE_URL="https://AWS_QUEUE_URL"

export AWS_PROFILE="lambda"

EMAIL_SUBJECT="Your Dumpster Fire is on the way!"
EMAIL_BODY=$(cat $DIR/reply.eml)

deleteMessage(){
  local handle="$1"

  echo "Deleting $handle"
  aws sqs delete-message --receipt-handle $handle --queue-url $QUEUE_URL
}

getMessages(){
  aws sqs receive-message \
    --wait-time-seconds 1 \
    --max-number-of-messages $NUM_MESSAGES \
    --queue-url $QUEUE_URL | jq -c -r '.Messages[]'
}

getQueueDepth(){
  aws sqs get-queue-attributes \
      --attribute-names All \
      --queue-url $QUEUE_URL \
  | jq -r '.Attributes.ApproximateNumberOfMessages'
}

while true; do
  # Set to one to kick off the loop; then process however many are in the queue
  QUEUE_DEPTH=1
  while [ $QUEUE_DEPTH -gt 0 ]; do
    QUEUE_DEPTH=$(getQueueDepth)
    if [ $QUEUE_DEPTH -gt 0 ]; then
      echo "$QUEUE_DEPTH messages in the queue; fetching up to 10"

      for msg in $(getMessages); do
        data=$(echo $msg | jq -r '.Body')
        receipt=$(echo $msg | jq -r '.ReceiptHandle')
        read -r EMAIL_ADDRESS POSITION KEY < <(echo $data | jq -r '.from, .position, .key'|xargs)

        # Sanity check the email address. Look for:
        # - no '@'
        # - missing local or domain portion
        # - postoffice@hey.com (loops are bad)
        PARTS=$(echo "$EMAIL_ADDRESS"|awk -F@ '{print NF}')
        read -r LOCAL_PART DOMAIN < <(echo "$EMAIL_ADDRESS"|awk -F@ '{print $1, $2}')

        if [ "$EMAIL_ADDRESS" == "" ] || [ $PARTS -lt 2 ] || [ "z$DOMAIN" == "z" ] || [ "$EMAIL_ADDRESS" == "postoffice@hey.com" ]; then
          echo "Bad Email Address; Deleting. ($EMAIL_ADDRESS)"
          deleteMessage "$receipt"
          continue
        fi


        BODY=$(echo "$EMAIL_BODY" | sed -e "s/POSITION/$POSITION/" | sed -e "s/KEY/$KEY/")
        set +e
        echo "$BODY" | mailx -a 'Content-Type: text/html' -s "$EMAIL_SUBJECT" -r "$FROM" -- "$EMAIL_ADDRESS"
        if [ $? -gt 0 ]; then
          echo "Error sending email to $EMAIL_ADDRESS"
        fi
        set -e
        deleteMessage "$receipt"
      done
    fi
  done
  sleep 10
done
