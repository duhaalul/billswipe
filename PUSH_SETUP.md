# Mengaktifkan notifikasi Android (FCM)

Lonceng dan kotak masuk memakai Supabase Realtime dan sudah dapat dipakai tanpa Firebase.
Push Android memerlukan konfigurasi berikut; belum aktif hanya dengan memasang aplikasi ini.

1. Buat proyek di https://console.firebase.google.com/ lalu tambahkan aplikasi Android dengan package `com.billswipe.billswipe`. Unduh `google-services.json`. File konfigurasi client ini bukan service-account private key.
2. Jalankan PowerShell `./tool/configure_firebase.ps1 -GoogleServicesPath PATH_FILE_JSON` untuk mengisi config.local.json dan resource Android yang diperlukan saat proses aplikasi ditutup. Pemetaan nilai: FIREBASE_API_KEY (client.api_key.current_key), FIREBASE_APP_ID (client.client_info.mobilesdk_app_id), FIREBASE_SENDER_ID (project_info.project_number), FIREBASE_PROJECT_ID (project_info.project_id). Ambil client yang package-nya cocok. Tidak perlu plugin Google Services karena Flutter memakai FirebaseOptions secara eksplisit.
3. Jalankan SQL supabase/migrations/202610040002_push_devices.sql di SQL Editor sekali.
4. Di Firebase Project settings > Service accounts, buat kredensial server. Simpan JSON service account sebagai secret `FIREBASE_SERVICE_ACCOUNT` di Supabase Edge Functions. Jangan memasukkan private key ke aplikasi, Git, atau chat.
5. Buat secret acak panjang `PUSH_WEBHOOK_SECRET` di Supabase Edge Functions. Deploy fungsi send-push (config.toml menonaktifkan pemeriksaan JWT; fungsi wajib memeriksa header rahasia sendiri).
6. Buat Database Webhook untuk INSERT pada public.notifications. URL: https://PROJECT_REF.supabase.co/functions/v1/send-push. Method POST. Header Content-Type application/json dan x-push-secret berisi PUSH_WEBHOOK_SECRET. Pastikan Firebase Cloud Messaging API aktif.
7. Build ulang dengan config.local.json. Login, buka lonceng, lalu Aktifkan notifikasi HP dan izinkan notifikasi Android.
8. Gunakan akun kedua untuk mengirim permintaan teman/tagihan. Uji foreground (badge), background dan aplikasi ditutup biasa (notifikasi sistem), ketuk notifikasi, tandai dibaca, logout/ganti akun, dan cabut izin notifikasi. Android force-stop bisa menghentikan pengiriman sampai aplikasi dibuka kembali.

Status push belum diuji langsung sebelum proyek Firebase, SQL, secret, dan webhook dikonfigurasi.
Notifikasi sistem memakai pesan umum supaya layar kunci tidak menampilkan nominal/nama. Ketukan membuka inbox hanya untuk akun penerima yang sedang login.
Jika fungsi mengembalikan 5xx, periksa log dan lakukan retry webhook. Pengiriman push best-effort; inbox Supabase tetap menjadi sumber notifikasi. Untuk produksi tambahkan antrean retry otomatis dan pemantauan pengiriman.
Konfigurasi ini menargetkan Android. Push iOS/APNs dan web belum dikonfigurasi.
