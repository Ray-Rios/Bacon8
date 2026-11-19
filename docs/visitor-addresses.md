Moved word for word from BACON8.md (§18) on 2026-11-19; BACON8.md keeps a short summary and links here.

## 18. Real visitor addresses

Found 2026-10-27, fixed in the hub 2026-11-04 (owner: "/admin/security ... shows all attacks coming through
as a docker desktop address completely stripping out the original IPs").

**Why the address was lost.** Docker Desktop forwards ports from Windows into its VM by proxying each
connection, so every visitor reaches ingress-nginx from `192.168.65.3`. No nginx or Kubernetes setting
can recover an address that never arrives. The 2026-10-27 work stopped that one address from being
blocked or locking everyone out, but the security page still saw one visitor.

**The fix has two halves.**

1. **In the hub** (done, 2026-11-04): `Bacon8Web.ClientIP` is the endpoint's first plug and the only code
   that reads forwarding headers (§6 invariant 19). It believes `X-Real-IP` (else the rightmost untrusted
   `X-Forwarded-For` hop) only when the connection itself comes from a private address, which in the
   cluster means ingress-nginx. Before this, five plugs and the sign-in pages each took the *first*
   `X-Forwarded-For` entry, which anyone can write. Tests: `test/bacon8_web/client_ip_test.exs`.
2. **In front of the cluster** (the owner's steps, `k3s/cloudflared/README.md`): a Cloudflare Tunnel.
   Two `cloudflared` pods dial out to Cloudflare; visitors reach Cloudflare, which sends their address
   in `CF-Connecting-IP`; ingress-nginx believes it only from the pods' range (`proxy-real-ip-cidr`) and
   passes it on as `X-Real-IP`. `scripts/deploy-prod.sh` applies both once the tunnel's token secret
   exists. It also hides the home address, lets the router's 80/443 forwards be closed, and puts
   Cloudflare's DDoS protection and CSAM Scanning Tool in front (§15).

Until the tunnel is up nothing changes on the page; afterwards new events show real addresses, which
the Block buttons and the automatic blocks accept. Older events keep `192.168.65.3`, as does anything
that still arrives through an open port forward (it can't be blocked, by design). Per-address limits
(registration, the API, `auth_login`) become per-visitor again at the same moment.

