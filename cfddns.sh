#!/bin/sh
set -e

usage() {
cat << EOF
Usage: $(basename "$0") [option...] <zone name> <record name>

Dynamic DNS using CloudFlare API.

Options:
    -p <proxy> (default false)
    -t <ttl>   (default 300)

Environment:
    CLOUDFLARE_TOKEN (required)

Dependencies:
    curl
    dig (from dnsutils)
    jq
EOF
}

bail() {
    code="$1"; shift
    [ $# -gt 0 ] && echo >&2 "$*"
    exit "$code"
}

ttl=300
proxy=false
while getopts 'pt:' opt; do
    case "$opt" in
        p) proxy=true ;;
        t) ttl="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

[ $# -ne 2 ] && usage && bail 1
[ -z "$CLOUDFLARE_TOKEN" ] && bail 1 "\$CLOUDFLARE_TOKEN not set"

readonly API_URL="https://api.cloudflare.com/client/v4"
readonly ZONE_NAME="$1"
readonly RECORD_NAME="$2"
readonly CLOUDFLARE_TOKEN

ipv4() {
    {
        dig +short myip.opendns.com @resolver1.opendns.com ||
        dig +short myip.opendns.com @resolver2.opendns.com ||
        dig TXT ch +short whoami.cloudflare @1.1.1.1 ||
        dig TXT +short o-o.myaddr.l.google.com @ns1.google.com ||
        dig TXT +short o-o.myaddr.l.google.com @ns2.google.com ||
        bail 1 "Failed to get IPv4 address"
    } | tr -d \"
}

# Usage: query METHOD ENDPOINT DATA
query() {
    q=$(
        curl -s -X"$1" \
            -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$3" \
            "$API_URL/zones${2}?name=${ZONE_NAME},${RECORD_NAME}"
    ) || return $?

    # Display error messages returned by api
    if [ "$(echo "$q" | jq .success)" != true ]; then
        echo "$q" | jq '.errors | .[] | .message' | tr -d \" >&2
        return 1
    fi

    echo "$q"
}

zoneid() {
    if [ -z "$_zoneid" ]; then
        q=$(query GET) ||
            bail 1 "Failed to get zone id"

        readonly _zoneid=$(
            echo "$q" |
            jq ".result | .[] | select(.name == \"$ZONE_NAME\") | .id" |
            tr -d \"
        )

        [ -z "$_zoneid" ] &&
            bail 1 "No zone with given name found"
    fi
    echo "$_zoneid"
}

recordid() {
    if [ -z "$_recordid" ]; then
        q=$(query GET "/$(zoneid)/dns_records") ||
            bail 1 "Failed to get record id"

        readonly _recordid=$(
            echo "$q" |
            jq ".result | .[] | select(.name == \"$RECORD_NAME\") | .id" |
            tr -d \"
        )

        [ -z "$_recordid" ] &&
            bail 1 "No record with given name found"
    fi
    echo "$_recordid"
}

update() {
    body=$(
        printf '{
            "type":"A",
            "name":"%s",
            "content":"%s",
            "ttl":%s,
            "proxied":%s
        }' "$RECORD_NAME" "$(ipv4)" "$ttl" "$proxy"
    )

    # Memoize both values and handle errors
    zoneid > /dev/null
    recordid > /dev/null

    query PUT "/$(zoneid)/dns_records/$(recordid)" "$body" > /dev/null ||
        bail 1 "Failed to update ip address"
}

update
