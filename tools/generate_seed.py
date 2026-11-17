"""Membuat supabase/seed.sql dari data kategori di bawah.
Jalankan: python3 tools/generate_seed.py
Admin juga bisa menambah kategori/tema/objek langsung di Supabase (Table Editor)
tanpa mengubah kode game."""
import json, os, random

random.seed(7)
BUDGETS = [500000, 1000000, 10000000, 100000000]
GRADE = [["Bekas", "Murah"], ["Standar", "Bagus"], ["Modern", "Berkualitas"], ["Premium", "Mewah"]]

# kategori: id, nama, warna, tag wajib, objek dasar (nama, tag, bentuk, warna, porsi harga)
CATS = [
 ("makanan", "Makanan", "#F59E0B", ["bahan", "masak", "saji", "dekor"], [
  ("Beras & Nasi", "bahan", "circle", "#F5F5DC", .05), ("Daging & Lauk", "bahan", "circle", "#B45309", .10),
  ("Sayur Segar", "bahan", "circle", "#22C55E", .04), ("Bumbu Rempah", "bahan", "circle", "#DC2626", .03),
  ("Kompor", "masak", "rect", "#6B7280", .12), ("Wajan & Panci", "masak", "circle", "#374151", .06),
  ("Piring Saji", "saji", "circle", "#FFFFFF", .05), ("Meja Saji", "saji", "rect", "#92400E", .10),
  ("Taplak & Bunga", "dekor", "rect", "#EC4899", .04), ("Lampu Hias", "dekor", "circle", "#FDE047", .05),
  ("Dessert & Kue", "bahan", "tri", "#F9A8D4", .06), ("Etalase", "saji", "rect", "#93C5FD", .14)],
  [["Hidangan sederhana", "Makanan jalanan"], ["Paket hidangan keluarga", "Menu warung makan"],
   ["Konsep restoran", "Menu restoran premium"], ["Restoran mewah", "Restoran eksklusif"]]),
 ("rumah", "Rumah", "#3B82F6", ["struktur", "lantai", "furnitur", "lampu", "dekor"], [
  ("Dinding & Cat", "struktur", "rect", "#E5E7EB", .10), ("Pintu", "struktur", "rect", "#92400E", .05),
  ("Jendela", "struktur", "rect", "#93C5FD", .05), ("Lantai Keramik", "lantai", "rect", "#D6D3D1", .10),
  ("Karpet", "lantai", "rect", "#B91C1C", .04), ("Sofa", "furnitur", "rect", "#1D4ED8", .12),
  ("Kasur", "furnitur", "rect", "#F3F4F6", .12), ("Lemari", "furnitur", "rect", "#78350F", .08),
  ("Meja", "furnitur", "rect", "#A16207", .06), ("Lampu Gantung", "lampu", "circle", "#FDE047", .05),
  ("Tanaman Hias", "dekor", "tri", "#16A34A", .03), ("Lukisan", "dekor", "rect", "#7C3AED", .04)],
  [["Dekorasi kamar sederhana", "Perbaikan kecil"], ["Renovasi kamar sederhana", "Ruang tamu hemat"],
   ["Renovasi interior", "Rumah minimalis"], ["Renovasi rumah besar", "Rumah mewah"]]),
 ("kolam", "Kolam Renang", "#06B6D4", ["kolam", "lantai", "santai", "dekor"], [
  ("Kolam Kecil", "kolam", "rect", "#22D3EE", .20), ("Kolam Besar", "kolam", "rect", "#0EA5E9", .30),
  ("Keramik Kolam", "lantai", "rect", "#BAE6FD", .08), ("Deck Kayu", "lantai", "rect", "#A16207", .08),
  ("Kursi Santai", "santai", "rect", "#FFFFFF", .05), ("Payung Pantai", "santai", "circle", "#F97316", .04),
  ("Gazebo", "santai", "rect", "#78350F", .12), ("Lampu Kolam", "dekor", "circle", "#FDE047", .04),
  ("Palem", "dekor", "tri", "#15803D", .04), ("Pot Bunga", "dekor", "circle", "#DB2777", .02)],
  [["Memperbaiki kolam rusak", "Kolam plastik halaman"], ["Renovasi kolam sederhana", "Kolam pribadi mini"],
   ["Kolam modern", "Kolam villa"], ["Kolam hotel", "Kolam resort mewah"]]),
 ("bisnis", "Bisnis", "#10B981", ["bangunan", "fasilitas", "perabot", "papan", "lampu"], [
  ("Bangunan Toko", "bangunan", "rect", "#E5E7EB", .20), ("Rak Barang", "fasilitas", "rect", "#9CA3AF", .06),
  ("Kasir", "fasilitas", "rect", "#111827", .08), ("Kulkas Display", "fasilitas", "rect", "#BFDBFE", .10),
  ("Meja Pelanggan", "perabot", "rect", "#A16207", .05), ("Kursi Pelanggan", "perabot", "circle", "#DC2626", .03),
  ("Papan Nama", "papan", "rect", "#F59E0B", .05), ("Neon Box", "papan", "rect", "#EC4899", .06),
  ("Lampu Toko", "lampu", "circle", "#FDE047", .04), ("Tanaman", "perabot", "tri", "#16A34A", .02)],
  [["Warung makan", "Toko kelontong"], ["Kafe kecil", "Salon"], ["Minimarket", "Toko pakaian"],
   ["Hotel", "Pusat perbelanjaan"]]),
 ("taman", "Taman & Lingkungan", "#22C55E", ["tanaman", "jalan", "fasilitas", "dekor"], [
  ("Rumput", "tanaman", "rect", "#4ADE80", .06), ("Pohon", "tanaman", "tri", "#15803D", .06),
  ("Bunga", "tanaman", "circle", "#F472B6", .03), ("Jalan Setapak", "jalan", "rect", "#D6D3D1", .06),
  ("Bangku Taman", "fasilitas", "rect", "#92400E", .05), ("Ayunan", "fasilitas", "tri", "#EF4444", .08),
  ("Perosotan", "fasilitas", "tri", "#3B82F6", .10), ("Air Mancur", "dekor", "circle", "#38BDF8", .12),
  ("Lampu Taman", "dekor", "circle", "#FDE047", .03), ("Patung", "dekor", "rect", "#A8A29E", .08)],
  [["Taman rumah", "Taman bunga"], ["Taman bermain", "Taman bunga besar"], ["Taman kota", "Area rekreasi"],
   ["Taman wisata", "Taman air"]]),
 ("interior", "Dekorasi Interior", "#A855F7", ["furnitur", "elektronik", "lampu", "dekor"], [
  ("Meja Kerja", "furnitur", "rect", "#78350F", .08), ("Kursi Gaming", "furnitur", "rect", "#DC2626", .08),
  ("Rak Dinding", "furnitur", "rect", "#A16207", .04), ("TV / Monitor", "elektronik", "rect", "#111827", .15),
  ("Speaker", "elektronik", "rect", "#374151", .06), ("Proyektor", "elektronik", "circle", "#6B7280", .12),
  ("LED Strip", "lampu", "rect", "#A855F7", .03), ("Lampu Meja", "lampu", "circle", "#FDE047", .02),
  ("Poster", "dekor", "rect", "#F43F5E", .02), ("Karpet Bulu", "dekor", "circle", "#E5E7EB", .04)],
  [["Setup gaming", "Kamar tidur"], ["Ruang kerja", "Ruang keluarga"], ["Studio musik", "Ruang streaming"],
   ["Bioskop pribadi", "Ruang hiburan"]]),
 ("otomotif", "Otomotif", "#EF4444", ["kendaraan", "modif", "alat", "dekor"], [
  ("Motor", "kendaraan", "rect", "#1F2937", .30), ("Mobil", "kendaraan", "rect", "#DC2626", .40),
  ("Velg", "modif", "circle", "#9CA3AF", .06), ("Cat Body", "modif", "rect", "#2563EB", .06),
  ("Lampu LED", "modif", "circle", "#FDE047", .03), ("Knalpot", "modif", "rect", "#6B7280", .04),
  ("Kunci & Perkakas", "alat", "rect", "#F59E0B", .03), ("Dongkrak Hidrolik", "alat", "rect", "#B91C1C", .07),
  ("Lantai Epoxy", "dekor", "rect", "#64748B", .06), ("Neon Garasi", "dekor", "rect", "#22D3EE", .03)],
  [["Modifikasi motor", "Cuci kendaraan"], ["Garasi rumah", "Modifikasi motor lengkap"],
   ["Bengkel", "Modifikasi mobil"], ["Showroom", "Mobil custom"]]),
 ("properti", "Properti & Wisata", "#F97316", ["bangunan", "kamar", "fasilitas", "dekor"], [
  ("Bangunan Utama", "bangunan", "rect", "#FDE68A", .25), ("Atap", "bangunan", "tri", "#B45309", .08),
  ("Kamar Tamu", "kamar", "rect", "#E0E7FF", .12), ("Resepsionis", "fasilitas", "rect", "#78350F", .06),
  ("Kolam", "fasilitas", "rect", "#22D3EE", .15), ("Restoran", "fasilitas", "rect", "#F59E0B", .10),
  ("Taman", "dekor", "tri", "#16A34A", .04), ("Lampu Jalan", "dekor", "circle", "#FDE047", .03),
  ("Gapura", "dekor", "rect", "#A8A29E", .05)],
  [["Penginapan sederhana", "Spot foto wisata"], ["Homestay", "Tempat wisata kecil"],
   ["Villa", "Kawasan rekreasi"], ["Resort", "Hotel / pusat hiburan"]]),
 ("fashion", "Fashion", "#EC4899", ["atasan", "bawahan", "aksesoris", "toko"], [
  ("Kaos / Kemeja", "atasan", "rect", "#F9FAFB", .06), ("Jaket", "atasan", "rect", "#1E3A8A", .10),
  ("Celana", "bawahan", "rect", "#1F2937", .06), ("Rok", "bawahan", "tri", "#BE185D", .06),
  ("Sepatu", "aksesoris", "rect", "#78350F", .08), ("Tas", "aksesoris", "rect", "#B45309", .08),
  ("Jam / Perhiasan", "aksesoris", "circle", "#FBBF24", .08), ("Manekin", "toko", "tri", "#E5E7EB", .04),
  ("Rak Baju", "toko", "rect", "#9CA3AF", .05), ("Cermin & Lampu", "toko", "circle", "#FDE047", .05)],
  [["Kombinasi pakaian", "Outfit harian"], ["Outfit pesta", "Lapak fashion"], ["Butik", "Koleksi pakaian"],
   ["Toko fashion premium", "Koleksi desainer"]]),
 ("teknologi", "Teknologi", "#6366F1", ["komputer", "periferal", "jaringan", "ruang"], [
  ("PC Rakitan", "komputer", "rect", "#111827", .20), ("Laptop", "komputer", "rect", "#9CA3AF", .15),
  ("Monitor", "periferal", "rect", "#1F2937", .08), ("Keyboard & Mouse", "periferal", "rect", "#374151", .03),
  ("Headset", "periferal", "circle", "#DC2626", .03), ("Router", "jaringan", "rect", "#E5E7EB", .03),
  ("Server Rack", "jaringan", "rect", "#0F172A", .15), ("Meja Komputer", "ruang", "rect", "#78350F", .05),
  ("AC", "ruang", "rect", "#F3F4F6", .06), ("RGB Lighting", "ruang", "rect", "#A855F7", .02)],
  [["Setup komputer", "Pojok belajar"], ["Ruang gaming", "Setup streaming"], ["Studio komputer", "Lab teknologi"],
   ["Pusat teknologi", "Data center mini"]]),
 ("umum", "Fasilitas Umum", "#64748B", ["bangunan", "ruang", "fasilitas", "akses"], [
  ("Gedung", "bangunan", "rect", "#E5E7EB", .25), ("Atap", "bangunan", "tri", "#B91C1C", .06),
  ("Ruang Kelas / Kamar", "ruang", "rect", "#FEF3C7", .10), ("Meja & Kursi", "ruang", "rect", "#A16207", .05),
  ("Lapangan", "fasilitas", "rect", "#22C55E", .12), ("Rak Buku", "fasilitas", "rect", "#78350F", .05),
  ("Toilet", "fasilitas", "rect", "#BFDBFE", .06), ("Parkiran", "akses", "rect", "#475569", .06),
  ("Ramp Difabel", "akses", "tri", "#F59E0B", .03), ("Lampu Jalan", "akses", "circle", "#FDE047", .02)],
  [["Pos ronda", "Taman baca"], ["Perpustakaan kecil", "Lapangan olahraga"], ["Sekolah", "Terminal"],
   ["Rumah sakit", "Stadion"]]),
]

def q(s):
    return "'" + s.replace("'", "''") + "'"

out = ["-- Dibuat otomatis oleh tools/generate_seed.py", "begin;"]
for si, (cid, cname, ccol, req, items, themes) in enumerate(CATS):
    out.append(f"insert into categories(id,name,color,sort) values ({q(cid)},{q(cname)},{q(ccol)},{si}) on conflict (id) do update set name=excluded.name, color=excluded.color;")
    for t, budget in enumerate(BUDGETS):
        for k, tname in enumerate(themes[t]):
            tid = f"{cid}_{t}_{k}"
            tags = random.sample(req, min(len(req), 3 + (t >= 2))) if len(req) > 3 else req
            arr = "array[" + ",".join(q(x) for x in tags) + "]::text[]"
            out.append(f"insert into themes(id,category_id,budget,name,required_tags,difficulty) values ({q(tid)},{q(cid)},{budget},{q(tname)},{arr},{t+1}) on conflict (id) do nothing;")
        for ii, (iname, tag, shape, col, share) in enumerate(items):
            for g in range(2):
                price = int(round(budget * share * (0.75 if g == 0 else 1.45) * random.uniform(0.85, 1.15), -3))
                price = max(price, 1000)
                quality = min(100, 30 + t * 15 + g * 15 + random.randint(-5, 5))
                iid = f"{cid}_{t}_{ii}_{g}"
                name = f"{iname} {GRADE[t][g]}"
                out.append(f"insert into items(id,category_id,budget,name,tag,price,quality,color,shape) values ({q(iid)},{q(cid)},{budget},{q(name)},{q(tag)},{price},{quality},{q(col)},{q(shape)}) on conflict (id) do nothing;")
out.append("insert into settings(key,value) values ('durations','[300,600,900,1200]') on conflict (key) do nothing;")
out.append("commit;")
path = os.path.join(os.path.dirname(__file__), "..", "supabase", "seed.sql")
open(path, "w").write("\n".join(out) + "\n")
print("ok", len(out))
