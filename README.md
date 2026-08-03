# image-webapp GitOps

Repository này là nguồn trạng thái deploy Kubernetes cho:

```text
ghcr.io/justlee2512/image-webapp
```

GitHub Actions ở source repo chỉ build/push image và cập nhật `newTag`.
Argo CD là thành phần duy nhất thực hiện deploy vào Kubernetes.

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

## 3. GHCR public hoặc private

Khuyến nghị đặt package GHCR thành public. Nếu giữ private, tạo pull secret rồi
thêm vào `Deployment.spec.template.spec.imagePullSecrets`:

```yaml
imagePullSecrets:
  - name: ghcr-pull-secret
```

## 4. TLS và hostname

Manifest mặc định dùng:

```text
image.chocomin.online
```

và TLS secret:

```text
image-webapp-tls
```

Đổi cả hai vị trí trong `apps/image-webapp/base/ingress.yaml` nếu dùng domain
khác. Nếu chưa có HTTPS, tạm bỏ khối `tls` và đặt `COOKIE_SECURE: "false"` trong
ConfigMap; production nên bật lại HTTPS và `COOKIE_SECURE: "true"`.

## 5. Khởi tạo database

Pipeline không chạy database migration. Trước deploy lần đầu hoặc khi
`db/init.sql` thay đổi:

```bash
psql -h 192.168.2.90 -U YOUR_DB_USER -d webapp -f db/init.sql
```

## 6. Tạo Argo CD Application

Argo CD của cluster đang dùng namespace `acgesd`:

```bash
kubectl apply -f argocd/application.yaml
```

Kiểm tra:

```bash
kubectl -n acgesd get application image-webapp
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
