-- =============================================
-- DATAMIND 2026 — Supabase Veritabanı Şeması
-- =============================================

-- 1. Oturumlar tablosu
CREATE TABLE IF NOT EXISTS sessions (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(255)  NOT NULL,
  speaker     VARCHAR(500),
  company     VARCHAR(255),
  start_time  VARCHAR(20),
  end_time    VARCHAR(20),
  is_active   BOOLEAN       DEFAULT FALSE,
  created_at  TIMESTAMPTZ   DEFAULT NOW()
);

-- 2. Katılımlar tablosu
CREATE TABLE IF NOT EXISTS attendances (
  id          SERIAL PRIMARY KEY,
  session_id  INTEGER       NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  first_name  VARCHAR(255)  NOT NULL,
  last_name   VARCHAR(255)  NOT NULL,
  email       VARCHAR(255)  NOT NULL,
  created_at  TIMESTAMPTZ   DEFAULT NOW(),
  CONSTRAINT unique_attendance UNIQUE (session_id, email)
);

-- 3. Oturumları ekle (5 oturum)
INSERT INTO sessions (name, speaker, company, start_time, end_time)
SELECT
  v.name,
  v.speaker,
  v.company,
  v.start_time,
  v.end_time
FROM (
  VALUES
    ('Oturum 1 – Açılış',  'Emre Doğan, Emin Doğan, Kerimcan Arslan', 'Experian / Hepsiburada / TOM', '10:00', '10:45'),
    ('Oturum 2',           'Tuğser Okur',                               'Lentatek',                     '11:00', '11:45'),
    ('Oturum 3',           'Alper Tunga',                               'Oricin',                       '12:45', '13:30'),
    ('Oturum 4',           'Burak Celal Akyüz',                         'Udemy',                        '13:45', '14:30'),
    ('Oturum 5',           'Kaan Can Yılmaz',                           'Ucanbie Technology',           '14:45', '15:30')
) AS v(name, speaker, company, start_time, end_time)
WHERE NOT EXISTS (SELECT 1 FROM sessions);

-- 4. Admin rol yönetimi (Supabase Auth üzerinden)
-- Not: auth.users içindeki ilk admini bir kere oluşturup, role tablosuna eklemen gerekir.
CREATE TABLE IF NOT EXISTS user_roles (
  user_id   uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role      text NOT NULL DEFAULT 'user',
  created_at timestamptz DEFAULT now()
);

-- Rol değerleri (admin, kapı görevlisi, varsayılan kullanıcı)
ALTER TABLE user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_check
  CHECK (role IN ('admin','user','door'));

-- Kapı kayıt (girişte elden alınan katılımcı bilgileri)
CREATE TABLE IF NOT EXISTS door_checkins (
  id            SERIAL PRIMARY KEY,
  first_name    VARCHAR(255) NOT NULL,
  last_name     VARCHAR(255) NOT NULL,
  phone         VARCHAR(50)  NOT NULL,
  registered_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Admin yetkisi olup olmadığını döndüren helper.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles r
    WHERE r.user_id = auth.uid()
      AND r.role = 'admin'
  );
$$;

-- Kapı kayıt görevlisi mi?
CREATE OR REPLACE FUNCTION public.is_door()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles r
    WHERE r.user_id = auth.uid()
      AND r.role = 'door'
  );
$$;

-- 5. Row Level Security
ALTER TABLE sessions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendances ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE door_checkins ENABLE ROW LEVEL SECURITY;

-- Herkes oturumları okuyabilir
DROP POLICY IF EXISTS "sessions_select" ON sessions;
CREATE POLICY "sessions_select"
  ON sessions FOR SELECT
  USING (true);

-- Admin oturumları güncelleyebilir (toggle)
DROP POLICY IF EXISTS "sessions_update" ON sessions;
CREATE POLICY "sessions_update"
  ON sessions FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Katılım kaydı: sadece aktif oturuma izin ver
DROP POLICY IF EXISTS "attendances_insert" ON attendances;
CREATE POLICY "attendances_insert"
  ON attendances FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.id = session_id
        AND s.is_active = true
    )
  );

-- Katılım listesini (ve çekiliş listesini) sadece admin görebilir
DROP POLICY IF EXISTS "attendances_select" ON attendances;
CREATE POLICY "attendances_select"
  ON attendances FOR SELECT
  USING (public.is_admin());

-- Kullanıcı sadece kendi rol kaydını okuyabilir
DROP POLICY IF EXISTS "user_roles_select_own" ON user_roles;
CREATE POLICY "user_roles_select_own"
  ON user_roles FOR SELECT
  USING (user_id = auth.uid());

-- Kapı kayıt: ekleme ve listeleme (kapı rolü veya admin)
DROP POLICY IF EXISTS "door_checkins_insert" ON door_checkins;
CREATE POLICY "door_checkins_insert"
  ON door_checkins FOR INSERT
  WITH CHECK (public.is_door() OR public.is_admin());

DROP POLICY IF EXISTS "door_checkins_select" ON door_checkins;
CREATE POLICY "door_checkins_select"
  ON door_checkins FOR SELECT
  USING (public.is_door() OR public.is_admin());

-- 5. Tüm oturumlara katılan kişileri döndüren view (çekiliş)
CREATE OR REPLACE VIEW raffle_candidates AS
SELECT
  first_name,
  last_name,
  email,
  COUNT(DISTINCT session_id) AS session_count
FROM attendances
GROUP BY first_name, last_name, email
HAVING COUNT(DISTINCT session_id) = (SELECT COUNT(*) FROM sessions);
