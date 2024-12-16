#!/bin/bash

#example ./script.sh "ADE" 
#arg choises ADE, APN and VPP

# parameters
tenantId="exxxxxxxx7868b2402"
clientId="8f7xxxxxxxxxxxd6"
clientSecret="Wxxxxxxxxxxxxxx"

# ANSI color codes
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if the correct number of arguments is provided
if [ "$#" -lt 1 ]; then
  echo -e "${YELLOW}Warning: Usage: $0 <outputType>${NC}"
  echo -e "${YELLOW}outputType options: ADE, APN, VPP${NC}"
  exit 1
fi

# Parameters
outputType=$1

# Get an access token
get_access_token() {
  response=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "scope=https://graph.microsoft.com/.default" \
    -d "client_id=$clientId" \
    -d "client_secret=$clientSecret" \
    "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token")
  
  accessToken=$(echo "$response" | jq -r '.access_token')

  if [ "$accessToken" == "null" ] || [ -z "$accessToken" ]; then
    echo "Error obtaining access token: $response" >&2
    exit 1
  fi
}

# Function to get ADE expiration date
get_ADE_expiration_date() {
  headers="Authorization: Bearer $accessToken"
  depOnboardingSettings=$(curl -s -H "$headers" "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings")
  
  expirationDate=$(echo "$depOnboardingSettings" | jq -r '.value[] | .tokenExpirationDateTime')
  
  if [ -z "$expirationDate" ]; then
    echo "Error getting ADE expiration date: $depOnboardingSettings" >&2
  else
    echo "$expirationDate"
  fi
}

# Function to get APN certificate expiration date
get_APN_certificate_expiration_date() {
  headers="Authorization: Bearer $accessToken"
  apn=$(curl -s -H "$headers" "https://graph.microsoft.com/v1.0/deviceManagement/applePushNotificationCertificate")
  
  expirationDate=$(echo "$apn" | jq -r '.expirationDateTime')
  
  if [ -z "$expirationDate" ]; then
    echo "Error getting APN certificate expiration date: $apn" >&2
  else
    echo "$expirationDate"
  fi
}

# Function to get VPP token expiration date
get_VPP_expiration_date() {
  headers="Authorization: Bearer $accessToken"
  vppTokens=$(curl -s -H "$headers" "https://graph.microsoft.com/beta/deviceAppManagement/vppTokens")
  
  expirationDate=$(echo "$vppTokens" | jq -r '.value[] | .expirationDateTime')
  
  if [ -z "$expirationDate" ]; then
    echo "Error getting VPP token expiration date: $vppTokens" >&2
  else
    echo "$expirationDate"
  fi
}

# Get and display the expiration date based on the output type
get_access_token

case $outputType in
  ADE)
    adeExpirationDate=$(get_ADE_expiration_date)
    echo "$adeExpirationDate"
    ;;
  APN)
    apnExpirationDate=$(get_APN_certificate_expiration_date)
    echo "$apnExpirationDate"
    ;;
  VPP)
    vppExpirationDate=$(get_VPP_expiration_date)
    echo "$vppExpirationDate"
    ;;
  *)
    echo -e "${YELLOW}Invalid output type. Please specify ADE, APN, or VPP.${NC}"
    exit 1
    ;;
esac