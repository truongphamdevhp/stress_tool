# Local Stress Tool

PowerShell tool để tạo tải giả lập cho CPU, RAM và disk IO nhằm test phần mềm khác trên cùng máy.

## Chạy nhanh

```powershell
.\stress-local.ps1 -CpuThreads 16 -RamMB 8192 -Seconds 120
```

## Ví dụ

CPU full theo số logical core của máy trong 60 giây:

```powershell
.\stress-local.ps1
```

CPU 12 luồng, giữ 16 GB RAM trong 5 phút:

```powershell
.\stress-local.ps1 -CpuThreads 12 -RamMB 16384 -Seconds 300
```

Thêm disk IO khoảng 200 MB/s, file tạm tự xóa khi dừng:

```powershell
.\stress-local.ps1 -CpuThreads 12 -RamMB 8192 -DiskMBps 200 -Seconds 180
```

## Tham số

- `-CpuThreads`: số worker CPU. `0` nghĩa là dùng toàn bộ logical core.
- `-RamMB`: dung lượng RAM cần giữ, tính bằng MB.
- `-DiskMBps`: tốc độ ghi disk mục tiêu, tính bằng MB/s. `0` nghĩa là tắt disk stress.
- `-Seconds`: thời gian chạy.
- `-Priority`: `BelowNormal`, `Normal`, hoặc `AboveNormal`. Mặc định là `BelowNormal`.

## Dừng

Nhấn `Ctrl+C` trong terminal. Script sẽ cố gắng stop worker jobs và xóa thư mục `stress-temp-*`.

Không nên đặt `-RamMB` quá sát dung lượng RAM vật lý, vì Windows có thể bắt đầu paging nặng và làm toàn hệ thống rất khó thao tác.
