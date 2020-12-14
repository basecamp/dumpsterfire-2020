/* AWS SES Lambda Actions must be written in javascript, as
 * far as I know, since it's the only runtime that provides
 * the third argument `callback`, which is required for flow
 * control handling back up in SES-land.
 */
var AWS = require("aws-sdk");

const rules_uri = "s3://dumpsterfire-rules/rules.json"

const s3 = new AWS.S3();

const asyncGetObject = async (params) => {
  return new Promise((resolve,reject) => {
    s3.getObject(params,function(err, result){
      if(err) reject(err);
      if(result) resolve(result);
    });
  })
}

const checkSpammy = (receipt) => {
  console.log("Checking spamminess");
  let spammy = (receipt.spfVerdict.status === 'FAIL'
    || receipt.dkimVerdict.status === 'FAIL'
    || receipt.dmarcVerdict.status === 'FAIL'
    || receipt.spamVerdict.status === 'FAIL'
    || receipt.virusVerdict.status === 'FAIL');

  if (spammy == true) {
    console.log('Dropping spam');
    console.log(`spf: ${receipt.spfVerdict.status}`);
    console.log(`dkim: ${receipt.dkimVerdict.status}`);
    console.log(`dmarc: ${receipt.dmarcVerdict.status}`);
    console.log(`spam: ${receipt.spamVerdict.status}`);
    console.log(`virus: ${receipt.virusVerdict.status}`);
  }

  return spammy;
}

module.exports.handler = async (event, context) => {
  console.log('Spam filter');
  var rules = { senders: [], domains:[], content: [], prefixes: [], version: 0 }

  try {
    const response = await asyncGetObject({Bucket: "dumpsterfire-rules", Key: "rules.json"});
    rulesObj = Object.assign(rules, JSON.parse(response.Body.toString()));
    console.log(rules);
  } catch (e) {
    console.log(e);
  }

  const blockList = rules.senders;
  const blockPrefixList = rules.prefixes;
  const blockDomainsList = rules.domains;

  const allowList = ["dumpsterfire@hey.com", "dumpster@hey.com"];
  const failsafeBlockList = ["postoffice@hey.com"];
  const failsafeBlockPrefixList = ["postmaster"];
  const sesNotification = event.Records[0].ses;
  const emailRegex = /<(.*)>/g;

  // Debugging
  //console.log("SES Notification:\n", JSON.stringify(sesNotification, null, 2));
  //console.log(`blockList: ${blockList.length}`);
  //console.log(`blockPrefixList: ${blockPrefixList.length}`);
  console.log("Loaded "+ (blockList.length + blockPrefixList.length + blockDomainsList.length) +" rules");

  var to = sesNotification.mail.commonHeaders.to[0];
  var from = sesNotification.mail.commonHeaders.returnPath;
  // Check if any spam check failed
  try {
    if (allowList.includes(to)) {
      let [localPart, domainPart] = from.split("@");

      if (failsafeBlockList.includes(from)
          || failsafeBlockPrefixList.includes(localPart)
          || blockList.includes(from)
          || blockPrefixList.includes(localPart)
          || blockDomainsList.includes(domainPart)) {

        console.log(`Blocked: ${from} in blocklists`);
        return { 'disposition': 'STOP_RULE_SET' };

      } else {
        var isSpammy = checkSpammy(sesNotification.receipt);
        if (isSpammy == true) {
          return { 'disposition': 'STOP_RULE_SET' };
        } else {
          console.log('Allow');
          return null;
        }
      }
    } else {
      console.log('Reject');
      return { 'disposition': 'STOP_RULE_SET' };
    }
  } catch(err) {
    console.log(sesNotification.mail.commonHeaders);
    return { 'disposition': 'STOP_RULE_SET' };
  }
};
