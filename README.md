# 🐋 docker_no_redhat ⚙️ v1.0

⚠️ **PENTING**: Skrip dan instruksi di repo ini hanya **untuk Debian / Ubuntu**.  
**Tidak** untuk Red Hat, CentOS, RHEL, atau turunan mereka.

Repository ini menyediakan **installer & uninstaller** sederhana untuk memasang **Docker Engine** di sistem berbasis Debian/Ubuntu.

---

## 📂 Persiapan Direktori & Clone Repo

Agar rapi, buat dulu direktori khusus untuk repositori ini, lalu lakukan `git clone`:

```bash
# 1️⃣ Buat direktori kerja
mkdir -p ~/copy
cd ~/copy

# 2️⃣ Clone repository
git clone https://github.com/KeiNode/docker_no_redhat.git
cd ~/copy/docker_no_redhat

🚀 Cara Menjalankan
1️⃣ Beri izin eksekusi (wajib dilakukan pertama kali)
chmod +x ./install.sh ./uninstall.sh

2️⃣ Jalankan installer
sudo bash ./install.sh

3️⃣ Jalankan uninstaller
sudo bash ./uninstall.sh


## 🩺 Troubleshooting (Masalah Umum) ##

🙂 Command tidak ditemukan / tidak bisa jalan

Pastikan bash terpasang → which bash

Pastikan file sudah memiliki izin eksekusi atau jalankan dengan bash ./install.sh

🛠 Gagal saat apt update atau apt install

Jalankan sudo apt update secara manual, lalu ulangi instalasi

Pastikan koneksi internet aktif dan tidak diblokir proxy

🔐 Permission denied

Jalankan dengan sudo

Pastikan user termasuk dalam grup sudo

🐳 Docker tidak berjalan setelah instalasi

Cek status service → sudo systemctl status docker

Cek log service → sudo journalctl -u docker --no-pager

♻️ Masih ada sisa file setelah uninstall

Cek paket tersisa: dpkg -l | grep -i docker

Hapus manual jika perlu:

sudo rm -rf /var/lib/docker

