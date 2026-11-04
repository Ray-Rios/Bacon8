# Real visitor addresses: Cloudflare Tunnel

**Why** (2026-11-04, BACON8.md §18). The site runs on Docker Desktop's Kubernetes. Docker Desktop
forwards ports from Windows into its VM by proxying the connection, so every visitor reaches
ingress-nginx from the VM's own address, `192.168.65.3`, and the real address is gone before nginx
sees anything. No nginx or Kubernetes setting can bring it back: `/admin/security`, the IP blocker,
the honeypot and every rate limit see one "visitor".

The fix is to stop accepting the internet through Docker Desktop's port forward at all. A Cloudflare
Tunnel runs as pods inside the cluster and dials *out* to Cloudflare; visitors connect to Cloudflare,
and Cloudflare tells us who they are in `CF-Connecting-IP`. nginx believes that header only from the
tunnel's pods, and the hub (`Bacon8Web.ClientIP`) only from nginx. It also hides the PC's home
address, takes the router's ports off the internet, and puts Cloudflare's CSAM Scanning Tool and DDoS
protection in front (BACON8.md §15).

## Setting it up (once)

1. **Put the domain on Cloudflare** (free plan): add the site at dash.cloudflare.com, then change the
   nameservers at the registrar to Cloudflare's. SSL/TLS mode: **Full (strict)**.
2. **Make the tunnel**: Zero Trust → Networks → Tunnels → Create a tunnel → Cloudflared, name it
   `bacon8`. Copy the token it shows (a secret) straight into the cluster, never into a file:
   ```sh
   read -r -s -p "Tunnel token: " T; echo
   kubectl create secret generic cloudflared-token -n bacon8 --from-literal=token="$T"; unset T
   ```
3. **Public hostnames** on the tunnel, one each for the site and `www`: service type **HTTPS**, URL
   `ingress-nginx-controller.ingress-nginx.svc.cluster.local:443`, and under TLS set **Origin Server
   Name** to that hostname (the certificate cert-manager made is for it). Add `mail.` the same way if
   the Mailhog page should stay reachable. Delete the A/AAAA records that pointed at the home address:
   the tunnel adds CNAMEs.
4. **Start the connectors and make nginx believe them**:
   ```sh
   kubectl apply -f k3s/cloudflared/cloudflared.yaml
   kubectl rollout status deployment/cloudflared -n bacon8
   kubectl get pods -n bacon8 -l app=cloudflared -o wide    # their IPs must be inside proxy-real-ip-cidr
   kubectl patch configmap ingress-nginx-controller -n ingress-nginx --type merge --patch-file k3s/cloudflared/ingress-nginx-real-ip.yaml
   ```
   (`scripts/deploy-prod.sh` re-applies both on every deploy once the token secret exists.)
5. **Check**: open the site from a phone on mobile data, then `/admin/security`: the newest events
   show the phone's public address, not `192.168.65.3`. In nginx's log:
   `kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=20`.
6. **Close the router's port forwards** for 80 and 443 to the PC. Nothing needs them now, and while
   they're open anyone can still reach nginx directly (harmless for addresses, as such requests stay
   `192.168.65.3`, but it skips Cloudflare's protection). Certificates still renew: Let's Encrypt's
   HTTP check reaches nginx through the tunnel.

## Undoing it

Re-open the port forwards, point the DNS records back at the home address, then
`kubectl delete -f k3s/cloudflared/cloudflared.yaml` and remove the four keys from the
`ingress-nginx-controller` ConfigMap (`kubectl edit configmap ingress-nginx-controller -n ingress-nginx`).
The hub needs no change either way.
