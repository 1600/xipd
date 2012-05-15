dnsserver = require "dnsserver"

NS_T_A     = 1
NS_T_NS    = 2
NS_T_CNAME = 5
NS_T_SOA   = 6
NS_C_IN    = 1
NS_RCODE_NXDOMAIN = 3
PATTERN    = /^[a-z0-9]{1,7}$/

exports.encode = encode = (ip) ->
  value = 0
  for byte, index in ip.split "."
    value += parseInt(byte, 10) << (index * 8)
  (value >>> 0).toString 36

exports.decode = decode = (string) ->
  return unless PATTERN.test string
  value = parseInt string, 36
  ip = []
  for i in [1..4]
    ip.push value & 0xFF
    value >>= 8
  ip.join "."

createSOA = (domain) ->
  mname   = "ns-1.#{domain}"
  rname   = "hostmaster.#{domain}"
  serial  = parseInt new Date().getTime() / 1000
  refresh = 28800
  retry   = 7200
  expire  = 604800
  minimum = 3600
  dnsserver.createSOA mname, rname, serial, refresh, retry, expire, minimum

matchIP = (parts) ->
  return if parts.length < 4
  matched = true
  for part in parts[0...4]
    part = parseInt part, 10
    matched = false unless 0 <= part <= 255
  matched

exports.createServer = (domain, address = "127.0.0.1") ->
  server = new dnsserver.Server
  domain = "#{domain}".toLowerCase()
  soa = createSOA domain

  parseHostname = (hostname) ->
    return unless hostname
    hostname = hostname.toLowerCase()
    offset = hostname.length - domain.length

    if domain is hostname.slice offset
      if 0 < offset
        subdomain = hostname.slice 0, offset - 1
        subdomain.split('.').reverse()
      else
        []

  encodeCname = (subdomain) ->
    if matchIP subdomain
      name = encode subdomain.slice(0, 4).reverse().join "."
      if subdomain.length > 4
        rest = subdomain.slice(4).reverse().join(".") + "."
      else
        rest = ""

      hostname = "#{rest}#{name}.#{domain}"
      dnsserver.createName hostname

  server.on "request", (req, res) ->
    q = req.question ? {}
    subdomain = parseHostname q.name

    if q.type is NS_T_A and q.class is NS_C_IN and subdomain?
      if cname = encodeCname subdomain
        res.addRR q.name, NS_T_CNAME, NS_C_IN, 600, cname
      else
        res.addRR q.name, NS_T_A, NS_C_IN, 600, decode(subdomain[0]) ? address

    else if q.type is NS_T_NS and q.class is NS_C_IN and subdomain?.length is 0
      res.addRR q.name, NS_T_SOA, NS_C_IN, 600, soa, true

    else
      res.header.rcode = NS_RCODE_NXDOMAIN

    res.send()

  server
