# PHASE 0 — DISCOVERY / VALIDATION REPORT

Ngày: 2026-08-29
Nguồn chính: HAR `remote.360auto.net(3).har` do người dùng cung cấp.

## Trạng thái

**Phase 0 — Discovery từ HAR: COMPLETED.**

Lưu ý: các kiểm tra cần thao tác/restart trực tiếp trên PC (đặc biệt stable ID qua restart) chưa được chứng minh chỉ bằng HAR; chúng được giữ là validation cần chạy trước khi bật automation production.

## 1. Runtime registry

HAR cho thấy WebSocket của Remote dùng snapshot `scr_list` / `scr_list_res` để đồng bộ danh sách client.

Một snapshot thực tế có các instance dạng:

```text
id = 0:client_14
idx = 0
name = XuyếnChiXàoTỏi
state = running/offline
cap = ok/wait/busy
capAge = ...
```

Identity runtime nên chuẩn hóa bằng `client_id` bỏ prefix transport `0:` khi mapping nội bộ; `idx` chỉ là vị trí snapshot và không được dùng làm identity.

## 2. Client-level control đã được capture

HAR đã bắt được action:

```json
{"t":"act","key":"root/1000#0","op":"row_toggle","r":0,"id":"snghg:1","epoch":0}
```

Remote nhận ACK:

```json
{"t":"act_result","id":"snghg:1","ok":true}
```

Các action tiếp theo dùng cùng `op=row_toggle`, với request id khác (`snghg:2`, `snghg:3`, ...), và đều có `act_result.ok=true`.

Đây là bằng chứng quan trọng rằng Remote có một **client/row-level toggle action**, khác với control ở product/app level.

## 3. Correlation với runtime state

Trong cùng WebSocket capture:

```text
client_14 = offline
        ↓
row_toggle r=0
        ↓
act_result ok=true
        ↓
client_14 = running, cap=wait
```

Sau các snapshot tiếp theo, client_14 tiếp tục ở `running` và sau chuỗi thao tác khác trở lại `offline`.

Một transition cuối capture thể hiện:

```text
client_14: running → offline
```

Do đó `row_toggle` được xác nhận là control path có tác động đến client row, nhưng semantics Start/Stop tuyệt đối không nên suy ra chỉ từ `row_toggle`; controller phải xác nhận desired transition bằng snapshot/delta sau ACK.

## 4. Bulk behavior

Có nhiều `row_toggle` được gửi gần nhau và nhận `act_result` riêng cho từng request. Vì vậy thiết kế scheduler có thể phát action theo từng client, giới hạn `maxParallel` và `stagger`, thay vì giả định một product-level stop/start duy nhất.

## 5. Product-level vs client-level

HAR cũng cho thấy control ở tầng product/app (`product_id=73`). Không dùng product-level `launch/stop` để đại diện cho Start/Stop từng client.

Kiến trúc chuẩn:

```text
Product/App control
    ≠
Client/Row control
```

AUTORELOG phải giữ hai tầng riêng biệt.

## 6. Snapshot / reconciliation

`scr_list` được gửi lặp lại và `scr_list_res` trả snapshot runtime. `act_result` chỉ xác nhận action request được xử lý/accepted; trạng thái cuối phải lấy từ runtime snapshot/delta.

Rule cho Agent:

```text
send intent
  ↓
wait act_result
  ↓
re-read runtime
  ↓
confirm desired transition
```

Không coi `act_result.ok=true` là bằng chứng client đã RUNNING/OFFLINE.

## 7. Stable identity

HAR chứng minh `client_id` hiện diện và được sử dụng ổn định trong snapshot của capture, ví dụ `0:client_14`. HAR không chứa một chu kỳ restart Auto/PC đủ để chứng minh ID bền vững qua restart.

**B1 = NOT YET VERIFIED.** Trước automation production phải thực hiện restart Auto, lấy snapshot lại, và nếu có thể restart PC rồi so sánh `client_id` với name/machine/room.

## 8. Heartbeat / reconnect

Plan v4 giữ baseline:

```text
heartbeat interval = 10s
heartbeat timeout  = 30s
reconnect = exponential backoff
```

HAR cho thấy nhiều WebSocket session/reconnect nhưng không đủ để đo và chứng minh timeout thực tế. Vì vậy đây là **design baseline**, không phải measured runtime result.

## 9. Security

HAR có thông tin session/auth trong transport. Không commit HAR nguyên bản vào repository. Nếu cần chia sẻ, scrub cookie, authorization, session, token và credential trước.

## 10. Phase 0 acceptance

| Item | Status |
|---|---|
| Runtime client discovery | PASS |
| `client_id` / `idx` distinction | PASS |
| Snapshot `scr_list_res` | PASS |
| Client-level `row_toggle` | PASS |
| `act_result` correlation | PASS |
| Runtime state reconciliation | PASS |
| Product-level vs client-level separation | PASS |
| Bulk per-client action observation | PASS |
| Stable ID across restart | **PENDING PC TEST** |
| Fixed/none/orphan live classification | **PENDING master/runtime reconciliation** |
| Group conflict validation | **PENDING master validation** |
| Heartbeat measured values | **PENDING runtime test** |

## 11. Gate trước Phase 1

Chỉ cần hoàn tất các validation còn pending trên PC/master:

1. restart Auto/PC để xác minh stable ID;
2. đối chiếu toàn bộ runtime với canonical master;
3. xác nhận `fixed`, `none`, `orphan/client_68`;
4. xác nhận group conflict;
5. test reconnect/heartbeat thực tế.

Sau các gate trên mới triển khai Agent control path. Không thay thế AutoCycle hiện tại trước migration/rollback plan.
