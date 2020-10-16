# CloudFlare Dynamic DNS

```
Usage: cfddns.sh [option...] <zone name> <record name>

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
```
