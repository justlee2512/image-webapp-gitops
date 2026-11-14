-- BEGIN image-webapp tunnel health
-- https://argo-cd.readthedocs.io/en/stable/operator-manual/health/
-- This checks route configuration, not HTTP availability through the tunnel.
do
  local metadata = obj.metadata or {}
  local annotations = metadata.annotations or {}
  if metadata.namespace == "image-webapp" and metadata.name == "image-webapp"
      and annotations["chocomin.online/ingress-health-mode"] == "cloudflare-tunnel" then
    if obj.spec and obj.spec.ingressClassName == "traefik" and obj.spec.rules then
      for _, rule in ipairs(obj.spec.rules) do
        if rule.host == "image.chocomin.online" and rule.http and rule.http.paths then
          for _, path in ipairs(rule.http.paths) do
            if path.path == "/" and path.pathType == "Prefix"
                and path.backend and path.backend.service
                and path.backend.service.name == "image-webapp"
                and path.backend.service.port and path.backend.service.port.name == "http"
                and annotations["traefik.ingress.kubernetes.io/router.entrypoints"] == "web" then
              return { status = "Healthy", message = "Tunnel route configured; no LoadBalancer address expected. HTTP availability must be checked separately." }
            end
          end
        end
      end
    end
    return { status = "Degraded", message = "Expected image-webapp tunnel route is missing or invalid" }
  end
end
-- END image-webapp tunnel health
