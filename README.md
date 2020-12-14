# df20

## Overview

1. Customer emails `dumpsterfire@hey.com`.
2. AWS SES receives email.

    1. SES checks for spam/dkim/spf
    2. SES sends headers to `email_filter` js lambda.
    3. SES drops email into s3 bucket `s3://dumpsterfire-bucket/inbound/`

3. S3 fires off SNS notification when email hits `/inbound`.
4. SNS triggers `processor` ruby lambda. This moves the email between 4 states, triggering a S3->SNS notification each time:

    1. /inbound -> lambda screens email for content size (<5MB)
    2. /screened -> lambda formats email body for printing
    3. /print -> lambda publishes message to SQS screener queue with job data, and another SQS queue for initial marketing response.
    4. /completed, but that happens in step 8.

5. SQS triggers `screener` ruby lambda. This reads the `s3://dumpsterfire-rules/rules.json` file and filters jobs accordingly, dumping the ones that pass into the print queue.
6. Raspberry Pi pulls message off SQS print queue for approval; either sending to the moderated queue or deleting the job from the queue.
7. The print loop pulls messages off the moderated queues (Normal, VIP, or Special), and prints/burns them.
6. Rasberry Pi puts message on SQS Queue when complete.
7. SQS triggers `cleanup` lambda. This puts a message on another SQS queue for final email response, and moves the file to `s3://dumpsterfire-bucket/completed/`.
8. S3 fires off SNS notification when email hits `/completed`
9  SNS triggers `processor` ruby lambda, which updates `s3://dumpsterfire-cloudfront/stats.json`.

## Infrastructure

Terraform bits are under `terraform`, ruby lambda code is under `lambdas/processor`, and node-red flows are under `node-red`.

Appropriately named `dumpster` profile needed in your `~/.aws/config`/`~/.aws/credentials` for this to work.

Generate a new lambda package:
```bash
for lambda in processor cleanup screener; do
    pushd lambdas/$lambda
    rake package
    mv *.zip ../../terraform/production/
    popd
done
pushd terraform/production
terraform apply -auto-approve
popd
```

## Email Filter

It's a javascript lambda because that's the only lambda runtime that supports callbacks, which are required for SES Actions to work correctly. (AFAICT)

```bash
pushd lambdas/email_filter
zip -r email_filter.zip index.js index-async.js node_modules package.json package-lock.json
mv email_filter.zip ../../terraform/production/
popd
pushd terraform/production
terraform apply -auto-approve
popd
```

## Hey Marketing Auto-reply

This is a systemd service running on a node authorized to send email from the hey domain. The service file is `/etc/systemd/system/reply.service`, and it runs `/path/to/hey-marketing-reply/reply.sh`. The script relies on the `aws` commands and credentials in my home directory. 😬

To update, copy the new script into `/path/to/hey-marketing-reply/reply.sh`, fix ownership if needed, and run `sudo systemctl restart reply.service`.

Logs are available via `sudo journalctl -f -u reply.service`.

Same for the `hey-marketing-complete-reply` mailer.
