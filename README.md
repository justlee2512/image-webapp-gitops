# image-webapp GitOps

Repository này là nguồn trạng thái deploy Kubernetes cho:

```text
ghcr.io/justlee2512/image-webapp
```

GitHub Actions ở source repo chỉ build/push image và cập nhật `newTag`.
Argo CD là thành phần duy nhất thực hiện deploy vào Kubernetes.

## Cluster đích

Đã kiểm tra chỉ đọc ngày 15/11/2026 qua context `default`, API `192.168.2.150:6443`:

- RKE2 `v1.37.2+rke2r1`: 2 control-plane và 2 worker, cả 4 node `Ready`.
- Argo CD chạy trong namespace `argocd`.
- IngressClass `traefik`; Service `kube-system/rke2-traefik` loại LoadBalancer,
  VIP `192.168.2.148`, HTTP `80`, HTTPS `443`.
- Traefik công bố địa chỉ Service qua `publishedService`; Ingress của app
  đã có địa chỉ `192.168.2.148` trong status.
- Cloudflare Tunnel phục vụ domain của app; `/health` qua HTTPS trả HTTP 200.
- Chưa có StorageClass; app hiện dùng `emptyDir` cho `/tmp`, không yêu cầu PVC.
- Namespace, Deployment, Service, Ingress và Argo CD Application `image-webapp`
  đã tồn tại. Deployment có 3/3 replica Ready; Application Synced / Healthy.

Các manifest giữ nguyên 3 replica và image tag hiện tại. Secret database/session
được quản lý ngoài Git; địa chỉ PostgreSQL trong ví dụ bên dưới không phải cấu
hình hạ tầng được repo này quản lý.

## Cấu trúc

```text
apps/image-webapp/base                 Manifest dùng chung
apps/image-webapp/overlays/production Production image tag
argocd/application.yaml               Argo CD Application
scripts/create-secret.sh              Tạo DB/session secret ngoài Git
```

## 1. Repository và phạm vi quản lý

```text
justlee2512/image-webapp-gitops
```

Repo đã tồn tại và Argo CD theo dõi nhánh `main`. Push lên `main` sẽ kích hoạt
auto sync. Repo chỉ quản lý ứng dụng `image-webapp`, không quản lý Traefik,
LoadBalancer, Cloudflare Tunnel hoặc ConfigMap cấu hình Argo CD.

Kiểm tra manifest local trước khi đề xuất deploy:

```bash
kubectl kustomize apps/image-webapp/overlays/production
git diff --check
```

## 2. Tạo application secret

Database không thuộc CI/CD. Secret được tạo trực tiếp trong cluster và không
commit lên Git:

```bash
export DATABASE_URL='postgresql://webapp:URL_ENCODED_PASSWORD@192.168.2.90:5432/webapp'
export SESSION_SECRET="$(openssl rand -base64 48)"
./scripts/create-secret.sh
```

Giữ `SESSION_SECRET` cố định. Nếu đổi giá trị này, các session đăng nhập hiện tại
sẽ không còn hợp lệ.

Script tạo Secret `image-drive` với hai key `database-url`, `session-secret`,
đúng với Deployment. Khi chạy lại, có thể bỏ biến `SESSION_SECRET` để script
tái sử dụng giá trị trong cluster. Khi chuyển từ cluster cũ, cần cung cấp lại
giá trị cũ nếu muốn giữ session.

## 3. GHCR public hoặc private

Khuyến nghị đặt package GHCR thành public. Nếu giữ private, tạo pull secret rồi
thêm vào `Deployment.spec.template.spec.imagePullSecrets`:

```yaml
imagePullSecrets:
  - name: ghcr-pull-secret
```

## 4. TLS và hostname

Manifest dùng hostname:

```text
image.chocomin.online
```

Ingress nhận HTTP trên entrypoint `web` của Traefik. Để công khai qua
Cloudflare Tunnel, cấu hình route cần giữ Host header của app. Origin nội bộ
có thể dùng Service DNS ổn định của Traefik:

```text
Hostname: image.chocomin.online
Service:  http://rke2-traefik.kube-system.svc.cluster.local:80
```

Domain `image.chocomin.online` hiện hoạt động. Giữ Host header gốc để Traefik
chọn đúng Ingress. HTTPS kết thúc tại Cloudflare, không cần TLS Secret trong namespace app
cho đường đi này. Bật chuyển hướng HTTPS tại Cloudflare và đổi
`COOKIE_SECURE: "true"` trong ConfigMap trước khi phục vụ production qua HTTPS.
Giá trị trong repo hiện vẫn là `false`; việc đổi chính sách cookie cần được
triển khai và kiểm tra đăng nhập riêng.

Nếu đổi domain, sửa `apps/image-webapp/base/ingress.yaml` và route tương ứng.
Các annotation NGINX cũ đã được bỏ vì controller là Traefik; chúng không áp dụng
giới hạn body 35 MB hoặc timeout 600 giây. Cấu hình hiện tại không đảm bảo các
giới hạn đó; cần kiểm tra upload/download qua tunnel với file lớn trước khi sử dụng.

## 5. Khởi tạo database

Pipeline không chạy database migration. Trước deploy lần đầu hoặc khi
`db/init.sql` thay đổi:

```bash
psql -h 192.168.2.90 -U YOUR_DB_USER -d webapp -f db/init.sql
```

## 6. Argo CD Application

Application hiện đã tồn tại; không cần tạo lại cho mỗi lần cập nhật manifest.
Lệnh dưới chỉ dành cho khởi tạo môi trường mới, sau khi đã tạo Secret và duyệt
deploy. Argo CD dùng namespace `argocd`:

```bash
kubectl apply -f argocd/application.yaml
```

Kiểm tra:

```bash
kubectl -n argocd get application image-webapp
kubectl -n image-webapp get deploy,pod,svc,ingress
kubectl -n image-webapp rollout status deployment/image-webapp
```

## 7. Luồng deploy

### Health của Ingress qua Cloudflare Tunnel

Traefik hiện dùng LoadBalancer và công bố VIP `192.168.2.148` vào
`status.loadBalancer.ingress`. Ingress dùng health check mặc định của Argo CD,
không cần annotation bỏ qua health, Lua tùy chỉnh hoặc thay đổi `argocd-cm`.
Không khai báo `status` hay cố định VIP trong manifest app: controller quản lý
trường này từ Service LoadBalancer của Traefik.

Nếu Ingress lại `Progressing`, kiểm tra địa chỉ của Traefik Service và Ingress
bằng các lệnh chỉ đọc:

```bash
kubectl -n kube-system get service rke2-traefik -o wide
kubectl -n image-webapp get ingress image-webapp -o yaml
```

Health của Deployment/pod vẫn dựa trên trạng thái rollout và các probe.
Kiểm tra đường truy cập Tunnel riêng bằng `curl -fsS https://image.chocomin.online/health`.

### Pipeline

```text
merge main
  -> GitHub Actions build image sha-<commit>
  -> push GHCR
  -> update production/kustomization.yaml
  -> Argo CD auto sync
  -> Kubernetes RollingUpdate
```

Không dùng `latest`, không đưa kubeconfig lên GitHub và không để GitHub Actions
kết nối production PostgreSQL.
