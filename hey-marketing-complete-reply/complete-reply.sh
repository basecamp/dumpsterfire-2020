#!/usr/bin/env bash
set -euo pipefail

PATH=/path/to/aws-sdk/bin:$PATH
ENABLE_MAIL=1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

NUM_MESSAGES=10
FROM="dumpsterfire@hey.com"
QUEUE_URL="https://AWS_QUEUE_URL"
VIDEO_URL="https://hey.science/dumpster-fire/clip/"

export AWS_PROFILE="lambda"

EMAIL_SUBJECT="Here's your own Dumpster Fire for 2020!"
EMAIL_BODY=$(cat $DIR/template.eml)
LINK_TEMPLATE='<a href="URL">URL</a>'

mail_enabled(){
  if [ $ENABLE_MAIL -eq 1 ]; then
    return 0
  else
    return 1
  fi
}

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
      DEFAULT_IFS=$IFS
      IFS=$'\n'
      for msg in $(getMessages); do
        IFS=$DEFAULT_IFS
        data=$(echo $msg | jq -r '.Body')
        receipt=$(echo $msg | jq -r '.ReceiptHandle')
        if [ "z$data" == "z" ]; then echo $msg; break; fi

        read -r EMAIL_ADDRESS KEY < <(echo $data | jq -r '.email, .id'|xargs)
        read -r MAIN_URL < <(echo $data | jq -r '.main.video'|xargs)


        for LINK in MAIN_URL; do
          if [ ${!LINK} != "NONE" ]; then
            TMP_LINK="${VIDEO_URL}?id=${!LINK}"
            read ${LINK} <<<$(echo $LINK_TEMPLATE|sed -e "s|URL|$TMP_LINK|g")
          else
            read ${LINK} <<<"Oops, our camera was offline, we're terribly sorry."
          fi
        done

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

        BODY="$EMAIL_BODY"
        for VRBL in KEY MAIN_URL; do
          BODY=$(echo "$BODY" | sed -e "s|$VRBL|${!VRBL}|g")
        done

        set +e
        if [ $ENABLE_MAIL -eq 1 ]; then
          echo "$BODY" | mailx -a 'Content-Type: text/html' -s "$EMAIL_SUBJECT" -r "$FROM" -- "$EMAIL_ADDRESS"
        else
          echo "$BODY"
        fi
        if [ $? -gt 0 ]; then
          echo "Error sending email to $EMAIL_ADDRESS"
        fi
        set -e
        mail_enabled && deleteMessage "$receipt"
        IFS=$'\n'
      done
    fi
  done
  sleep 10
done
