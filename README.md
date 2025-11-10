# 🐧 docker_no_redhat ⚙️ v1.0

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

