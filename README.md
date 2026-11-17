# BUDGET BATTLE
**YOUR BUDGET, YOUR CREATIVITY, YOUR VICTORY.**

Game Android. Dua peserta mendapat budget virtual yang sama, kategori dan tema yang sama, lalu membangun dan mendekorasi. Setelah waktu habis, server menilai hasil keduanya dan menampilkannya berdampingan.

## Teknologi dan alasannya
| Bagian | Teknologi | Alasan |
|---|---|---|
| Game Android | **Godot 4.3** (GDScript) | Gratis, APK-nya ringan, mendukung 2D dan 3D, dan bisa di-build otomatis di GitHub Actions. |
| Server + database | **Supabase** (PostgreSQL) | Login aman, database online, dan aturan keamanan per baris (RLS). Semua aturan permainan berjalan sebagai fungsi SQL di server, jadi tidak bisa dicurangi dari HP. |
| Build | **GitHub Actions** | Menghasilkan APK dan ZIP tanpa perlu PC. |

## Struktur folder
```
project.godot            pengaturan game
export_presets.cfg       pengaturan export Android
icon.svg                 ikon aplikasi
scenes/Main.tscn         scene utama
scripts/main.gd          semua layar (menu, gameplay, hasil, admin, dll.)
scripts/build3d.gd       area bangun 3D (model 3D, cahaya, bayangan, kamera orbit)
scripts/api.gd           koneksi ke server (login, data, pertandingan)
scripts/config.gd        alamat server (diisi otomatis dari GitHub Secrets)
supabase/schema.sql      database + logika server (match, bot, penilaian, ranking)
supabase/seed.sql        11 kategori, 88 tema, 904 objek
tools/generate_seed.py   pembuat seed.sql
.github/workflows/build.yml  build APK + ZIP
```

## Fitur yang sudah berjalan
- 4 budget: Rp500.000, Rp1.000.000, Rp10.000.000, dan Rp100.000.000. Tiap budget punya objek, harga, kualitas, dan tema sendiri.
- 11 kategori: Makanan, Rumah, Kolam Renang, Bisnis, Taman, Interior, Otomotif, Properti, Fashion, Teknologi, dan Fasilitas Umum.
- **Player vs Player online sungguhan**: matchmaking acak (ranked), buat room, gabung pakai kode, nama dan avatar lawan, status online, reconnect lewat tombol "Lanjutkan pertandingan", dan karya tersimpan otomatis tiap 3 detik.
- **Player vs Bot**: bot berjalan di server dengan level Easy, Normal, Hard, dan Expert. Strategi tiap level berbeda dan sudah diuji (nilai rata-rata 39, 88, 90, dan 95). Bot tidak bisa melebihi budget dan tidak melihat karya pemain.
- Waktu dikendalikan server: 5, 10, 15, atau 20 menit (bisa diubah admin). Ada countdown, dan hasil dikunci saat waktu habis.
- Validasi budget di server: objek harus asli, harga dihitung ulang di server, dan total tidak boleh melebihi budget.
- Penilaian transparan: Kreativitas 30, Estetika 25, Kesesuaian tema 20, Efisiensi 15, Kelengkapan 10.
- Halaman hasil berdampingan, lengkap dengan animasi nilai, efek kemenangan, detail objek, Main Lagi, dan Bagikan.
- Profil dengan level, XP, koin, win rate, dan statistik PvP serta bot yang dipisah. Leaderboard ranked, mingguan, bulanan, dan total kemenangan. Peringkat Bronze sampai Master (pertandingan bot tidak dihitung). Ada juga riwayat, gelar, dan achievement.
- Panel admin di dalam aplikasi: aktif/nonaktif kategori, ubah harga dan status objek, atur durasi, blokir pemain.

## Yang belum ada (jujur)
- Model 3D dibuat dari bentuk dasar 3D (kotak, tabung, bola, prisma) per jenis objek: sofa, kasur, mobil, pohon, lampu, gedung, dll. Belum model hasil desainer (file .glb).
- Voting penonton, misi harian/mingguan, dan unggah model 3D dari dalam aplikasi belum dibuat. Untuk sementara, admin menambah objek dan gambar lewat Supabase Table Editor.
- Fitur "Bagikan" menyalin teks hasil ke clipboard.

## Cara memasang (dari HP)
Ikuti langkah dari asisten satu per satu. Ringkasnya:
1. Buat proyek di supabase.com, lalu jalankan `supabase/schema.sql`, kemudian `supabase/seed.sql` di SQL Editor.
2. Ambil Project URL dan anon key, lalu simpan sebagai GitHub Secrets `SUPABASE_URL` dan `SUPABASE_ANON_KEY`.
3. Upload proyek ke GitHub. Actions akan membuat APK, yang bisa diunduh dari tab Actions → Artifacts.
4. Supaya akunmu jadi admin, jalankan perintah ini di SQL Editor: `update profiles set is_admin = true where username = 'NAMAMU';`

**Jangan pernah** menaruh `service_role key` atau password database di GitHub.
