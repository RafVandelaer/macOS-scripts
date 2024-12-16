#!/bin/bash

#example: ./zabbix-intune-all-arguments.sh "efccb476-07c8-4c09-be3d-6xxxxxx8b2402" "8f726c80-6474xxxxxxxc4-35907a3e9d6" "WCI8Q~HaZ961N6xxxxxxxxxxezhAT4nCBF6DaBC" "ADE"

# ANSI color codes
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if the correct number of arguments is provided
if [ "$#" -lt 4 ]; then
  echo -e "${YELLOW}Warning: Usage: $0 <tenantId> <clientId> <clientSecret> <outputType>${NC}"
  echo -e "${YELLOW}outputType options: ADE, APN, VPP${NC}"
  exit 1
fi

# Parameters
tenantId=$1
clientId=$2
clientSecret=$3
outputType=$4

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
    echo "Invalid output type. Please specify ADE, APN, or VPP."
    exit 1
    ;;
esac