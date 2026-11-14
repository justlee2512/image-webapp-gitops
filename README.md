# image-webapp GitOps

Repository này là nguồn trạng thái deploy Kubernetes cho:

```text
ghcr.io/justlee2512/image-webapp
```

GitHub Actions ở source repo chỉ build/push image và cập nhật `newTag`.
Argo CD là thành phần duy nhất thực hiện deploy vào Kubernetes.

## Cluster đích

Đã kiểm tra ngày 14/11/2026 qua context `default`, API `192.168.2.150:6443`:

- RKE2 `v1.37.2+rke2r1`: 2 control-plane và 2 worker, cả 4 node `Ready`.
- Argo CD chạy trong namespace `argocd`.
- IngressClass `traefik`; Service `kube-system/rke2-traefik`, NodePort
  HTTP `30080`, HTTPS `30443`.
- Cloudflare Tunnel có 2 replica, chuyển HTTP nội bộ tới Traefik.
- Chưa có StorageClass; app hiện dùng `emptyDir` cho `/tmp`, không yêu cầu PVC.
- Chưa có namespace, Secret hoặc Argo CD Application của `image-webapp`.

Các manifest giữ nguyên 3 replica và image tag hiện tại. PostgreSQL
`192.168.2.90:5432` là địa chỉ từ cấu hình cũ, chưa xác minh kết nối từ cluster mới.

## Cấu trúc

```text
apps/image-webapp/base                 Manifest dùng chung
apps/image-webapp/overlays/production Production image tag
argocd/application.yaml               Argo CD Application
scripts/create-secret.sh              Tạo DB/session secret ngoài Git
```

## 1. Push repository

Tạo repository:

```text
justlee2512/image-webapp-gitops
```

Sau đó:

```bash
git init
git branch -M main
git add .
git commit -m "Initial image-webapp GitOps manifests"
git remote add origin https://github.com/justlee2512/image-webapp-gitops.git
git push -u origin main
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
Cloudflare Tunnel, thêm Published application route trong tunnel hiện có:

```text
Hostname: image.chocomin.online
Service:  http://rke2-traefik.kube-system.svc.cluster.local:80
```

Tại thời điểm kiểm tra, tunnel chỉ có route cho Argo CD và Headlamp; chưa có
route cho `image.chocomin.online`. Giữ Host header gốc để Traefik chọn đúng
Ingress. HTTPS kết thúc tại Cloudflare, không cần TLS Secret trong namespace app
cho đường đi này. Bật chuyển hướng HTTPS tại Cloudflare và đổi
`COOKIE_SECURE: "true"` trong ConfigMap trước khi phục vụ production qua HTTPS.
Giá trị hiện tại `false` cho phép kiểm tra HTTP nội bộ trước khi cấu hình tunnel.

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

## 6. Tạo Argo CD Application

Push các thay đổi lên `main` và tạo Secret trước khi tạo Application, vì Argo CD
đọc manifest từ Git và tự động sync ngay. Argo CD dùng namespace `argocd`:

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
