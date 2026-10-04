# Mengaktifkan akun dan teman

Kode sudah tersedia, tetapi layanan online memerlukan konfigurasi proyek Supabase. Mode tanpa akun tetap dapat dipakai. Konfirmasi pembayaran otomatis belum terhubung ke penyedia pembayaran.

1. Buka SQL Editor proyek Supabase. Jalankan seluruh isi `supabase/migrations/202610040001_accounts_and_friends.sql` sekali dalam satu eksekusi. Skrip membuat profil, permintaan teman, tagihan, notifikasi, aturan akses, dan bucket QRIS privat.
2. Di Authentication → URL Configuration, tambahkan redirect URL `com.billswipe.billswipe://login-callback`. Untuk mencoba web, tambahkan `http://localhost:7357` dan jalankan Chrome dengan port 7357.
3. Email/password: aktifkan provider Email. Jika konfirmasi email aktif, konfirmasikan email sebelum login. Untuk penggunaan nyata, atur SMTP proyek agar pengiriman email andal.
4. Google: buka Authentication → Sign In / Providers → Google. Buat OAuth client **Web application** di Google Cloud. Masukkan callback URL yang ditampilkan Supabase sebagai Authorized redirect URI di Google Cloud. Isi Client ID dan Client Secret di pengaturan provider Google Supabase, lalu aktifkan provider. Client Secret hanya disimpan di dashboard, tidak di Flutter.
5. Salin `config.example.json` menjadi `config.local.json`, lalu isi Project URL dan **publishable/anon key**. Jangan gunakan secret/service_role key di aplikasi.
6. Jalankan `flutter run -d ID_HP --dart-define-from-file=config.local.json`, atau `flutter run -d chrome --web-port=7357 --dart-define-from-file=config.local.json`.

## Pemeriksaan dua akun sebelum digunakan

- Buat akun A dan B. Keduanya memperoleh kode teman berbeda.
- A mengirim permintaan ke kode B. A belum dapat mengirim tagihan ke B sebelum B menerima.
- B menolak: tidak ada hubungan teman. Untuk versi pertama, pasangan yang ditolak tidak dapat mengirim ulang permintaan.
- Uji pasangan lain yang menerima: masing-masing masuk daftar teman.
- Unggah QRIS milik A lewat ikon QRIS. Buat tagihan, pilih B dari teman, tetapkan item, dan kirim.
- B melihat notifikasi dan tagihan dengan nominal yang sama, lalu dapat melihat QRIS A.
- Pengiriman ulang untuk tagihan/orang yang sama tidak membuat tagihan duplikat. Jika nominal berubah setelah dikirim, buat tagihan baru.
- Akun C tidak boleh membaca profil privat, QRIS, tagihan, atau notifikasi A/B. Client tidak memiliki izin mengubah status tagihan menjadi paid.

## Batas fitur pembayaran dan notifikasi

Notifikasi saat ini adalah kotak masuk dalam aplikasi yang diperbarui melalui Supabase Realtime. Integrasi push Android tersedia dan memerlukan konfigurasi tambahan di PUSH_SETUP.md. Push iOS/APNs belum disiapkan.

QRIS adalah gambar statis milik tiap akun. Pengguna membayar dengan aplikasi bank/e-wallet. BillSwipe tidak memindahkan uang dan tidak menandai transaksi lunas berdasarkan tombol pengguna. Integrasi status otomatis harus dibuat dengan penyedia pembayaran yang mendukung model penerimaan dana tiap pengguna; jangan memakai akun merchant tunggal tanpa menentukan penerima dana. Verifikasi webhook, nominal, identitas transaksi, dan idempotensi harus ada di server sebelum mengaktifkan status paid.

Referensi: [Supabase Flutter Auth](https://supabase.com/docs/guides/getting-started/tutorials/with-flutter), [Google login](https://supabase.com/docs/guides/auth/social-login/auth-google), [notifikasi transaksi Midtrans](https://docs.midtrans.com/docs/https-notification-webhooks).

## Konfirmasi email dengan OTP

Di Supabase buka Authentication > Email Templates (atau Emails > Templates) > Confirm sign up.
Konfigurasikan custom SMTP terlebih dahulu jika dashboard mewajibkannya untuk mengedit template. Ganti body dengan isi `supabase/templates/confirm_signup.html`, lalu Save. Subject: Kode konfirmasi BillSwipe.
Tetap aktifkan Confirm email. Placeholder {{ .Token }} menghasilkan kode sekali pakai.
Aplikasi memverifikasi kode lewat verifyOTP type email; pengiriman ulang memakai resend type signup.
Untuk akun yang sudah didaftarkan: masuk dengan email dan password. Jika email belum dikonfirmasi, layar OTP terbuka; tekan Kirim ulang kode setelah template disimpan.
Uji kode salah/kedaluwarsa, kode terbaru yang benar, dan kirim ulang. Pengujian email nyata memerlukan template dashboard dan penerimaan email pengguna.
