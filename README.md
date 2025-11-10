# docker_no_redhat ⚙️ v1.0


⚠️ **PENTING**: Skrip dan instruksi di repo ini hanya **untuk Debian / Ubuntu**. **Tidak** untuk Red Hat, CentOS, RHEL, atau turunan mereka.


Ringkasan: repo ini berisi skrip installer dan uninstaller sederhana untuk memasang Docker di sistem berbasis Debian/Ubuntu.


---


## Cara menjalankan


1. Pastikan file punya izin eksekusi (jika perlu):


```bash
chmod +x ./install.sh ./uninstall.sh

Menjalankan installer (jalankan sebagai root atau pakai sudo):

sudo bash ./install.sh

Menjalankan uninstaller (untuk menghapus instalasi yang dibuat skrip):

sudo bash ./uninstall.sh
Izin & keamanan

Skrip ini membutuhkan akses root karena akan menginstal paket sistem (apt, mengubah konfigurasi, menambahkan grup docker, dsb.).

Pastikan Anda membaca isi install.sh sebelum menjalankan bila menjalankan di server produksi.

Troubleshooting (Masalah Umum)

🙂 Tidak bisa jalan / command not found

Pastikan bash terpasang: which bash.

Pastikan file memiliki permission eksekusi atau jalankan dengan bash ./install.sh.

🛠 Gagal saat apt update atau mengunduh paket

Jalankan sudo apt update lalu ulangi.

Periksa koneksi jaringan dan konfigurasi proxy.

🔐 Permission denied saat menulis file atau service

Jalankan dengan sudo.

Pastikan user Anda ada di grup sudo.

🐳 Service Docker tidak berjalan setelah install

Cek status service: sudo systemctl status docker.

Lihat log: sudo journalctl -u docker --no-pager.

♻️ Sisa file setelah uninstall

Uninstaller mencoba membersihkan paket/konfigurasi yang dibuat skrip. Jika masih ada, periksa:

dpkg -l | grep -i docker

/var/lib/docker (jalankan sudo rm -rf /var/lib/docker jika yakin ingin menghapus data)

Catatan tambahan

Script bertujuan otomatisasi sederhana untuk development dan lab. Untuk production, ikuti panduan resmi Docker.

Jika ingin menambahkan banner atau mengubah nama pembuat di footer, edit file install.sh (placeholder banner akan dimasukkan di sana).

Pembuat: A.Z.L✍️
