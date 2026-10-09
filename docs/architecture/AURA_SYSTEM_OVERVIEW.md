# AURA System Overview

Sơ đồ này tổng quát hóa mã nguồn, dữ liệu, luồng xử lý AI, trạng thái triển khai hiện tại và kiến trúc AWS Release 1 của AURA tại ngày 2026-09-30.

![AURA system overview](../../diagrams/aura_system_overview_01_flowchart_master.png)

[Mermaid source](../../diagrams/aura_system_overview_01_flowchart_master.mmd) · [Scalable SVG](../../diagrams/aura_system_overview_01_flowchart_master.svg)

## Cách đọc

- Màu xanh lá và đường liền: hệ thống đang chạy hoặc luồng mã nguồn hiện tại đã được kiểm tra.
- Màu xanh dương: frontend, backend và deterministic contract-first advisor.
- Màu tím: nhánh external AI dùng LlamaIndex, hybrid retrieval và LangGraph; nhánh này có feature flag và hiện đang tắt trên backend public.
- Màu cam và đường nét đứt: AWS Release 1 đã có Terraform, workflow và script triển khai nhưng chưa `terraform apply`, chưa có EC2/DNS AWS thực tế.

## Kết luận kiến trúc

1. Đường chạy công khai hiện tại là người dùng → Vercel React frontend → Vercel `/api` rewrite → Render FastAPI backend.
2. `/api/chat` ưu tiên deterministic contract-first pipeline: intent → query frame → product resolution → catalog tools → evidence → response composition → verification/domain contract.
3. Lịch sử chat và conversation state được phía trình duyệt giữ có TTL 5 phút rồi gửi lại backend; backend không lưu chat dài hạn trong đường chạy hiện tại.
4. External AI workflow chỉ chạy khi `ENABLE_EXTERNAL_AI_WORKFLOW=true`; nó dùng LlamaIndex/ReAct, BM25 + Chroma/RRF, Tavily tùy chọn và LangGraph cho research/verification/correction.
5. AWS Release 1 dùng kiến trúc production-oriented: ZoneDNS CNAME → AWS ALB dual-stack + ACM → private EC2 `t3a.small` → Nginx → FastAPI, cùng ECR, SSM, encrypted EBS, S3 backup, CloudWatch, Budget và GitHub OIDC. EC2 chỉ nhận port 8080 từ security group của ALB.

## Evidence boundaries

- Kiểm tra live ngày 2026-09-30: frontend trả HTTP 200; backend `/health` trả `status=ok`, `catalog_products=391`, `external_workflow_enabled=false`.
- Terraform và workflow AWS tồn tại trong repository, nhưng sơ đồ không xem chúng là hạ tầng đã được tạo.
- NAT Gateway, RDS, ASG, Kubernetes và multi-AZ application replicas không thuộc Release 1. ALB được dùng để có TLS managed, IPv4/IPv6 và health-aware ingress; nó không tạo multi-AZ application replicas.
