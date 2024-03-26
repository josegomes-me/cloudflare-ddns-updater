#!/bin/bash
## change to "bin/sh" when necessary

auth_email=""                                       # The email used to login 'https://dash.cloudflare.com'
auth_method="token"                                 # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key=""                                         # Your API Token or Global API Key
zone_identifier=""                                  # Can be found in the "Overview" tab of your domain
record_names=("example.com" "sub.example.com")      # Which list record names you want to be synced
ttl="3600"                                          # Set the DNS TTL (seconds)
proxy="false"                                       # Set the proxy to true or false
sitename=""                                         # Title of site "Example Site"
slackchannel=""                                     # Slack Channel #example
slackuri=""                                         # URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
discorduri=""                                       # URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"


for record_name in "${record_names[@]}"; do
  ###########################################
  ## Check if we have a public IP
  ###########################################
  ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
  ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
  if [[ ! $ret == 0 ]]; then # In case Cloudflare fails to return an IP.
      ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
  else
      ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
  fi

  if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
      logger -s "DDNS Updater: Failed to find a valid IP."
      continue  # Skip to the next record_name
  fi

  ###########################################
  ## Check and set the proper auth header
  ###########################################
  if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
  else
    auth_header="Authorization: Bearer"
  fi

  ###########################################
  ## Seek for the A record
  ###########################################
  logger "DDNS Updater: Check Initiated for $record_name"
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                        -H "X-Auth-Email: $auth_email" \
                        -H "$auth_header $auth_key" \
                        -H "Content-Type: application/json")

  ###########################################
  ## Check if the domain has an A record
  ###########################################
  if [[ $record == *"\"count\":0"* ]]; then
    logger -s "DDNS Updater: Record does not exist for $record_name, perhaps create one first? (${ip})"
    continue  # Skip to the next record_name
  fi

  ###########################################
  ## Get existing IP and compare
  ###########################################
  old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
  
  if [[ $ip == $old_ip ]]; then
    logger "DDNS Updater: IP ($ip) for ${record_name} has not changed."
    continue  # Skip to the next record_name
  else
    logger "DDNS Updater: IP ($ip) for ${record_name} changed. Send e-mail."

     # E-mail data
    SUBJECT="DDNS Update Notification for $record_name"
    BODY="The DDNS record for $record_name has been successfully updated to $ip."
    TO="hi@josegomes.me"
    FROM="hi@josegomes.me"
    
    # Send e-mail
    (
    echo "From: $FROM"
    echo "To: $TO"
    echo "Subject: $SUBJECT"
    echo
    echo "$BODY"
    ) | sendmail -t
  fi

  ###########################################
  ## Set the record identifier from result
  ###########################################
  record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

  ###########################################
  ## Change the IP@Cloudflare using the API
  ###########################################
  update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                         -H "X-Auth-Email: $auth_email" \
                         -H "$auth_header $auth_key" \
                         -H "Content-Type: application/json" \
                         --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")

  ###########################################
  ## Report the status
  ###########################################
  # This is a simplified representation. You might want to check the response more thoroughly in a real script.
  if [[ $update == *"\"success\":false"* ]]; then
    logger -s "DDNS Updater: Update failed for $record_name with IP $ip."
  else
    logger "DDNS Updater: $record_name updated successfully to IP $ip."
  fi

done  # End of the for loop
