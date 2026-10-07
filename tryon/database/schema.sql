-- =====================================================================
-- TryOn: киімді 3D манекенге кигізіп көруге болатын интернет-дүкеннің дерекқоры
-- СУБД: SQLite 3.25+ (Django-ның әдепкі СУБД-сы). PostgreSQL-ге көшіруге болады.
-- Негізгі принциптер:
--   1) Ақша бүтін санмен, теңгемен сақталады (KZT, тиынсыз) — дөңгелектеу қатесі жоқ.
--   2) Тапсырыс жолында атау мен баға «снимок» ретінде сақталады: тауар кейін өзгерсе, тарих бұзылмайды.
--   3) Қойма қалдығы тек stock_movements (қозғалыс журналы) арқылы өзгереді.
--   4) Мәртебе ауысулары кестемен (order_transitions) басқарылады, триггер тексереді.
--   5) Рөл шектеулері (клиент/сатушы) триггермен қорғалады.
--   6) Отыру логикасы (қысады / дәл / бос) VIEW арқылы SQL-де есептеледі, шектері fit_rules кестесінде.
-- =====================================================================
PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- 1. АНЫҚТАМАЛЫҚТАР (lookup)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
  id   INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE CHECK (code IN ('client','seller','manager','admin')),
  name TEXT NOT NULL
);

CREATE TABLE garment_types (            -- киім түрі: қай «слотқа» киіледі
  code TEXT PRIMARY KEY,                -- tee, sweater, shorts, pants, sneakers
  name TEXT NOT NULL,
  slot TEXT NOT NULL CHECK (slot IN ('top','bottom','shoes'))
);

CREATE TABLE size_labels (              -- өлшем белгілері және олардың реті
  label TEXT PRIMARY KEY,               -- XS..XXL, 38..46
  rank  INTEGER NOT NULL UNIQUE,
  kind  TEXT NOT NULL CHECK (kind IN ('clothes','shoes'))
);

CREATE TABLE order_statuses (
  code       TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE order_transitions (        -- рұқсат етілген мәртебе ауысулары (деректер ретінде)
  from_status TEXT NOT NULL REFERENCES order_statuses(code),
  to_status   TEXT NOT NULL REFERENCES order_statuses(code),
  PRIMARY KEY (from_status, to_status)
);

CREATE TABLE return_reasons (
  code            TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  is_size_related INTEGER NOT NULL CHECK (is_size_related IN (0,1))   -- жүйенің басты көрсеткіші
);

CREATE TABLE fit_rules (                -- отыру шектері (см). diff = киім өлшемі − дене өлшемі
  zone        TEXT PRIMARY KEY CHECK (zone IN ('chest','hem','waist','hip','thigh')),
  tight_below REAL NOT NULL,            -- diff осыдан аз болса: «қысады»
  loose_above REAL NOT NULL,            -- diff осыдан көп болса: «бос»
  CHECK (tight_below < loose_above)
);

-- ---------------------------------------------------------------------
-- 2. ПАЙДАЛАНУШЫЛАР
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id            INTEGER PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,                       -- ешқашан ашық құпия сөз емес
  full_name     TEXT NOT NULL,
  phone         TEXT,
  role_id       INTEGER NOT NULL REFERENCES roles(id),
  is_active     INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),   -- пайдаланушыны жоймаймыз, өшіреміз
  created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE seller_profiles (          -- 1:1, тек сатушыға
  user_id     INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  shop_name   TEXT NOT NULL UNIQUE,
  description TEXT,
  is_verified INTEGER NOT NULL DEFAULT 0 CHECK (is_verified IN (0,1)),
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE body_profiles (            -- 1:1, тек клиентке: манекен осы деректерден құрылады
  user_id        INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  sex            TEXT NOT NULL DEFAULT 'n' CHECK (sex IN ('m','f','n')),
  height_cm      INTEGER NOT NULL CHECK (height_cm BETWEEN 120 AND 230),
  weight_kg      REAL    NOT NULL CHECK (weight_kg BETWEEN 30 AND 250),
  chest_cm       REAL    NOT NULL CHECK (chest_cm BETWEEN 50 AND 200),
  waist_cm       REAL    NOT NULL CHECK (waist_cm BETWEEN 40 AND 200),
  hip_cm         REAL    NOT NULL CHECK (hip_cm   BETWEEN 60 AND 200),
  measures_source TEXT   NOT NULL DEFAULT 'estimated' CHECK (measures_source IN ('estimated','manual')),
  updated_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE addresses (
  id              INTEGER PRIMARY KEY,
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label           TEXT,
  city            TEXT NOT NULL,
  street          TEXT NOT NULL,
  house           TEXT NOT NULL,
  apartment       TEXT,
  recipient_phone TEXT NOT NULL,
  is_default      INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1))
);
CREATE UNIQUE INDEX ux_addresses_one_default ON addresses(user_id) WHERE is_default = 1;

-- ---------------------------------------------------------------------
-- 3. КАТАЛОГ
-- ---------------------------------------------------------------------
CREATE TABLE categories (
  id        INTEGER PRIMARY KEY,
  name      TEXT NOT NULL,
  slug      TEXT NOT NULL UNIQUE,
  parent_id INTEGER REFERENCES categories(id) ON DELETE SET NULL
);

CREATE TABLE products (                 -- бір жазба = бір дизайн (түсі мен өрнегі бар)
  id          INTEGER PRIMARY KEY,
  seller_id   INTEGER NOT NULL REFERENCES users(id),
  category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  garment_type TEXT NOT NULL REFERENCES garment_types(code),
  name        TEXT NOT NULL,
  description TEXT,
  price       INTEGER NOT NULL CHECK (price > 0),                       -- теңге
  color_hex   TEXT NOT NULL DEFAULT '#cccccc' CHECK (length(color_hex) = 7 AND substr(color_hex,1,1) = '#'),
  pattern     TEXT NOT NULL DEFAULT 'solid' CHECK (pattern IN ('solid','stripe','check','dot')),
  print_kind  TEXT CHECK (print_kind IN ('logo','star','image')),
  is_active   INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_images (
  id         INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  path       TEXT NOT NULL,
  kind       TEXT NOT NULL DEFAULT 'photo' CHECK (kind IN ('photo','print')),  -- print: 3D киімге жапсырылатын сурет
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE product_sizes (            -- өлшем кестесі + қалдық. 3D шаблон мен өлшем ұсынысы осыдан алады
  id         INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  size_label TEXT NOT NULL REFERENCES size_labels(label),
  sku        TEXT NOT NULL UNIQUE,
  chest_cm   REAL CHECK (chest_cm > 0),    -- топ: кеуде, етек
  hem_cm     REAL CHECK (hem_cm   > 0),
  waist_cm   REAL CHECK (waist_cm > 0),    -- төменгі киім: бел, жамбас, сан
  hip_cm     REAL CHECK (hip_cm   > 0),
  thigh_cm   REAL CHECK (thigh_cm > 0),
  length_cm  REAL CHECK (length_cm > 0),
  stock_qty  INTEGER NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),   -- тек stock_movements арқылы өзгереді
  UNIQUE (product_id, size_label)
);

-- ---------------------------------------------------------------------
-- 4. САТЫП АЛУ: себет, тапсырыс, төлем, қайтару
-- ---------------------------------------------------------------------
CREATE TABLE cart_items (
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_size_id INTEGER NOT NULL REFERENCES product_sizes(id) ON DELETE CASCADE,
  qty             INTEGER NOT NULL CHECK (qty > 0),
  added_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, product_size_id)
);

CREATE TABLE orders (
  id              INTEGER PRIMARY KEY,
  customer_id     INTEGER NOT NULL REFERENCES users(id),             -- жоюға тыйым (RESTRICT)
  status          TEXT NOT NULL DEFAULT 'new' REFERENCES order_statuses(code),
  address_id      INTEGER REFERENCES addresses(id) ON DELETE SET NULL,
  ship_city       TEXT NOT NULL,                                     -- мекенжай «снимогы»
  ship_street     TEXT NOT NULL,
  ship_house      TEXT NOT NULL,
  ship_apartment  TEXT,
  ship_phone      TEXT NOT NULL,
  total_amount    INTEGER NOT NULL DEFAULT 0 CHECK (total_amount >= 0),  -- order_items триггерімен жаңарады
  manager_id      INTEGER REFERENCES users(id),
  last_changed_by INTEGER REFERENCES users(id),                      -- мәртебені кім өзгертті (қолданба жазады)
  created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
  id              INTEGER PRIMARY KEY,
  order_id        INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_size_id INTEGER NOT NULL REFERENCES product_sizes(id) ON DELETE RESTRICT,
  product_name    TEXT    NOT NULL,                                  -- снимок
  unit_price      INTEGER NOT NULL CHECK (unit_price > 0),           -- снимок (теңге)
  qty             INTEGER NOT NULL CHECK (qty > 0),
  UNIQUE (order_id, product_size_id)
);

CREATE TABLE order_status_history (
  id         INTEGER PRIMARY KEY,
  order_id   INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  status     TEXT NOT NULL REFERENCES order_statuses(code),
  changed_by INTEGER REFERENCES users(id),
  changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE payments (
  id           INTEGER PRIMARY KEY,
  order_id     INTEGER NOT NULL REFERENCES orders(id),
  amount       INTEGER NOT NULL CHECK (amount > 0),
  method       TEXT NOT NULL CHECK (method IN ('card','kaspi','cash')),
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed')),
  external_ref TEXT,                                                 -- сыртқы төлем жүйесінің нөмірі
  created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paid_at      TEXT
);

CREATE TABLE return_requests (
  id            INTEGER PRIMARY KEY,
  order_item_id INTEGER NOT NULL REFERENCES order_items(id),
  qty           INTEGER NOT NULL CHECK (qty > 0),
  reason_code   TEXT NOT NULL REFERENCES return_reasons(code),
  comment       TEXT,
  status        TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','rejected','refunded')),
  handled_by    INTEGER REFERENCES users(id),
  created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at    TEXT
);

CREATE TABLE refunds (                  -- қайтару бойынша ақша қайтарылуы
  id               INTEGER PRIMARY KEY,
  payment_id       INTEGER NOT NULL REFERENCES payments(id),
  return_request_id INTEGER NOT NULL UNIQUE REFERENCES return_requests(id),
  amount           INTEGER NOT NULL CHECK (amount > 0),
  created_at       TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 5. ҚОЙМА ЖУРНАЛЫ
-- ---------------------------------------------------------------------
CREATE TABLE stock_movements (          -- қалдықтың жалғыз ақиқат көзі
  id              INTEGER PRIMARY KEY,
  product_size_id INTEGER NOT NULL REFERENCES product_sizes(id),
  delta           INTEGER NOT NULL CHECK (delta <> 0),
  reason          TEXT NOT NULL CHECK (reason IN ('restock','order','cancel','return','adjust')),
  order_item_id   INTEGER REFERENCES order_items(id),
  return_request_id INTEGER REFERENCES return_requests(id),
  created_by      INTEGER REFERENCES users(id),
  created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 6. ТryOn-ның ЕРЕКШЕЛІКТЕРІ: отыру тарихы, образдар, таңдаулылар, хабарлама
-- ---------------------------------------------------------------------
CREATE TABLE fit_checks (               -- клиент өлшемді манекенде қарағанда жазылады: қайтарудың азаюын өлшеу үшін
  id              INTEGER PRIMARY KEY,
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_size_id INTEGER NOT NULL REFERENCES product_sizes(id) ON DELETE CASCADE,
  verdict         TEXT NOT NULL CHECK (verdict IN ('tight','fit','loose')),
  was_recommended INTEGER NOT NULL DEFAULT 0 CHECK (was_recommended IN (0,1)),
  created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE outfits (                  -- «қуыршақ ойыны»: сақталған образ
  id         INTEGER PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE outfit_items (
  outfit_id  INTEGER NOT NULL REFERENCES outfits(id) ON DELETE CASCADE,
  slot       TEXT NOT NULL CHECK (slot IN ('top','bottom','shoes')),
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  size_label TEXT REFERENCES size_labels(label),
  PRIMARY KEY (outfit_id, slot)
);

CREATE TABLE favorites (
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, product_id)
);

CREATE TABLE notifications (
  id         INTEGER PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('order_status','return_status','back_in_stock')),
  message    TEXT NOT NULL,
  order_id   INTEGER REFERENCES orders(id) ON DELETE SET NULL,
  is_read    INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0,1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 7. ИНДЕКСТЕР (сыртқы кілттер мен жиі сүзгілер)
-- ---------------------------------------------------------------------
CREATE INDEX ix_users_role            ON users(role_id);
CREATE INDEX ix_products_seller       ON products(seller_id, is_active);
CREATE INDEX ix_products_category     ON products(category_id, is_active);
CREATE INDEX ix_products_garment      ON products(garment_type);
CREATE INDEX ix_images_product        ON product_images(product_id, sort_order);
CREATE INDEX ix_sizes_product         ON product_sizes(product_id);
CREATE INDEX ix_orders_customer       ON orders(customer_id, created_at);
CREATE INDEX ix_orders_status         ON orders(status);
CREATE INDEX ix_items_order           ON order_items(order_id);
CREATE INDEX ix_items_size            ON order_items(product_size_id);
CREATE INDEX ix_history_order         ON order_status_history(order_id, changed_at);
CREATE INDEX ix_payments_order        ON payments(order_id, status);
CREATE INDEX ix_returns_item          ON return_requests(order_item_id);
CREATE INDEX ix_returns_status        ON return_requests(status);
CREATE INDEX ix_movements_size        ON stock_movements(product_size_id, created_at);
CREATE INDEX ix_fitchecks_user        ON fit_checks(user_id, created_at);
CREATE INDEX ix_notifications_user    ON notifications(user_id, is_read, created_at);
CREATE INDEX ix_favorites_product     ON favorites(product_id);

-- ---------------------------------------------------------------------
-- 8. ТРИГГЕРЛЕР: тұтастық және бизнес-логика
-- ---------------------------------------------------------------------
-- 8.1 Рөл шектеулері
CREATE TRIGGER trg_seller_profile_role BEFORE INSERT ON seller_profiles
WHEN (SELECT r.code FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=NEW.user_id) IS NOT 'seller'
BEGIN SELECT RAISE(ABORT,'seller_profiles: пайдаланушының рөлі «сатушы» емес'); END;

CREATE TRIGGER trg_body_profile_role BEFORE INSERT ON body_profiles
WHEN (SELECT r.code FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=NEW.user_id) IS NOT 'client'
BEGIN SELECT RAISE(ABORT,'body_profiles: пайдаланушының рөлі «клиент» емес'); END;

CREATE TRIGGER trg_products_seller_ins BEFORE INSERT ON products
WHEN (SELECT r.code FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=NEW.seller_id) IS NOT 'seller'
BEGIN SELECT RAISE(ABORT,'products: seller_id сатушыға тиесілі болуы керек'); END;

CREATE TRIGGER trg_products_seller_upd BEFORE UPDATE OF seller_id ON products
WHEN (SELECT r.code FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=NEW.seller_id) IS NOT 'seller'
BEGIN SELECT RAISE(ABORT,'products: seller_id сатушыға тиесілі болуы керек'); END;

CREATE TRIGGER trg_orders_customer_role BEFORE INSERT ON orders
WHEN (SELECT r.code FROM users u JOIN roles r ON r.id=u.role_id WHERE u.id=NEW.customer_id) IS NOT 'client'
BEGIN SELECT RAISE(ABORT,'orders: тапсырыс тек клиентке жасалады'); END;

-- 8.2 Өлшем кестесі: киім түріне қарай міндетті өлшемдер
CREATE TRIGGER trg_sizes_top_ins BEFORE INSERT ON product_sizes
WHEN (SELECT gt.slot FROM products p JOIN garment_types gt ON gt.code=p.garment_type WHERE p.id=NEW.product_id)='top'
     AND (NEW.chest_cm IS NULL OR NEW.hem_cm IS NULL)
BEGIN SELECT RAISE(ABORT,'Топ үшін кеуде (chest_cm) және етек (hem_cm) міндетті'); END;

CREATE TRIGGER trg_sizes_bottom_ins BEFORE INSERT ON product_sizes
WHEN (SELECT gt.slot FROM products p JOIN garment_types gt ON gt.code=p.garment_type WHERE p.id=NEW.product_id)='bottom'
     AND (NEW.waist_cm IS NULL OR NEW.hip_cm IS NULL OR NEW.thigh_cm IS NULL)
BEGIN SELECT RAISE(ABORT,'Төменгі киім үшін бел, жамбас және сан өлшемдері міндетті'); END;

CREATE TRIGGER trg_sizes_kind_ins BEFORE INSERT ON product_sizes
WHEN (SELECT gt.slot FROM products p JOIN garment_types gt ON gt.code=p.garment_type WHERE p.id=NEW.product_id)='shoes'
     AND (SELECT kind FROM size_labels WHERE label=NEW.size_label) IS NOT 'shoes'
BEGIN SELECT RAISE(ABORT,'Аяқ киімге аяқ киім өлшемі (38–46) таңдалуы керек'); END;

CREATE TRIGGER trg_sizes_kind_clothes BEFORE INSERT ON product_sizes
WHEN (SELECT gt.slot FROM products p JOIN garment_types gt ON gt.code=p.garment_type WHERE p.id=NEW.product_id)<>'shoes'
     AND (SELECT kind FROM size_labels WHERE label=NEW.size_label) IS NOT 'clothes'
BEGIN SELECT RAISE(ABORT,'Киімге киім өлшемі (XS–XXL) таңдалуы керек'); END;

-- 8.3 Қойма: қалдық тек журнал арқылы
CREATE TRIGGER trg_movement_apply AFTER INSERT ON stock_movements
BEGIN
  UPDATE product_sizes SET stock_qty = stock_qty + NEW.delta WHERE id = NEW.product_size_id;
END;

CREATE TRIGGER trg_back_in_stock AFTER UPDATE OF stock_qty ON product_sizes
WHEN OLD.stock_qty = 0 AND NEW.stock_qty > 0
BEGIN
  INSERT INTO notifications(user_id, kind, message)
  SELECT f.user_id, 'back_in_stock',
         '«' || (SELECT name FROM products WHERE id = NEW.product_id) || '» тауарының ' || NEW.size_label || ' өлшемі қайта қоймада'
  FROM favorites f WHERE f.product_id = NEW.product_id;
END;

-- 8.4 Тапсырыс жолдары
CREATE TRIGGER trg_item_order_open BEFORE INSERT ON order_items
WHEN (SELECT status FROM orders WHERE id = NEW.order_id) IS NOT 'new'
BEGIN SELECT RAISE(ABORT,'Тапсырыс жолын тек «new» мәртебесіндегі тапсырысқа қосуға болады'); END;

CREATE TRIGGER trg_item_product_active BEFORE INSERT ON order_items
WHEN (SELECT p.is_active FROM product_sizes ps JOIN products p ON p.id=ps.product_id WHERE ps.id = NEW.product_size_id) = 0
BEGIN SELECT RAISE(ABORT,'Тауар сатылымнан алынған'); END;

CREATE TRIGGER trg_item_stock_check BEFORE INSERT ON order_items
WHEN (SELECT stock_qty FROM product_sizes WHERE id = NEW.product_size_id) < NEW.qty
BEGIN SELECT RAISE(ABORT,'Қоймада қалдық жеткіліксіз'); END;

CREATE TRIGGER trg_item_after_insert AFTER INSERT ON order_items
BEGIN
  INSERT INTO stock_movements(product_size_id, delta, reason, order_item_id)
  VALUES (NEW.product_size_id, -NEW.qty, 'order', NEW.id);
  UPDATE orders SET total_amount = total_amount + NEW.qty * NEW.unit_price, updated_at = CURRENT_TIMESTAMP
  WHERE id = NEW.order_id;
END;

CREATE TRIGGER trg_item_immutable BEFORE UPDATE ON order_items
BEGIN SELECT RAISE(ABORT,'Тапсырыс жолын өзгертуге болмайды (бас тартып, жаңасын жасаңыз)'); END;

CREATE TRIGGER trg_order_no_delete BEFORE DELETE ON orders
BEGIN SELECT RAISE(ABORT,'Тапсырысты жоюға болмайды: «cancelled» мәртебесін қойыңыз'); END;

-- 8.5 Тапсырыс мәртебесінің өмірлік циклі
CREATE TRIGGER trg_order_created AFTER INSERT ON orders
BEGIN
  INSERT INTO order_status_history(order_id, status, changed_by) VALUES (NEW.id, NEW.status, NEW.last_changed_by);
END;

CREATE TRIGGER trg_order_transition BEFORE UPDATE OF status ON orders
WHEN NEW.status <> OLD.status
 AND NOT EXISTS (SELECT 1 FROM order_transitions WHERE from_status = OLD.status AND to_status = NEW.status)
BEGIN SELECT RAISE(ABORT,'Рұқсат етілмеген мәртебе ауысуы'); END;

CREATE TRIGGER trg_order_status_changed AFTER UPDATE OF status ON orders
WHEN NEW.status <> OLD.status
BEGIN
  INSERT INTO order_status_history(order_id, status, changed_by) VALUES (NEW.id, NEW.status, NEW.last_changed_by);
  INSERT INTO notifications(user_id, kind, message, order_id)
  VALUES (NEW.customer_id, 'order_status',
          'Тапсырыс №' || NEW.id || ': ' || (SELECT name FROM order_statuses WHERE code = NEW.status), NEW.id);
  UPDATE orders SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER trg_order_cancel_restock AFTER UPDATE OF status ON orders
WHEN NEW.status = 'cancelled' AND OLD.status <> 'cancelled'
BEGIN
  INSERT INTO stock_movements(product_size_id, delta, reason, order_item_id)
  SELECT product_size_id, qty, 'cancel', id FROM order_items WHERE order_id = NEW.id;
END;

-- 8.6 Төлем: толық төленсе, тапсырыс «paid» болады
CREATE TRIGGER trg_payment_paid_ins AFTER INSERT ON payments
WHEN NEW.status = 'paid'
BEGIN
  UPDATE orders SET status = 'paid'
  WHERE id = NEW.order_id AND status = 'new'
    AND (SELECT COALESCE(SUM(amount),0) FROM payments WHERE order_id = NEW.order_id AND status = 'paid') >= total_amount;
END;

CREATE TRIGGER trg_payment_paid_upd AFTER UPDATE OF status ON payments
WHEN NEW.status = 'paid' AND OLD.status <> 'paid'
BEGIN
  UPDATE orders SET status = 'paid'
  WHERE id = NEW.order_id AND status = 'new'
    AND (SELECT COALESCE(SUM(amount),0) FROM payments WHERE order_id = NEW.order_id AND status = 'paid') >= total_amount;
END;

-- 8.7 Қайтару
CREATE TRIGGER trg_return_delivered BEFORE INSERT ON return_requests
WHEN (SELECT o.status FROM order_items oi JOIN orders o ON o.id = oi.order_id WHERE oi.id = NEW.order_item_id) IS NOT 'delivered'
BEGIN SELECT RAISE(ABORT,'Қайтаруды тек жеткізілген («delivered») тапсырыс бойынша жасауға болады'); END;

CREATE TRIGGER trg_return_qty BEFORE INSERT ON return_requests
WHEN NEW.qty > (SELECT qty FROM order_items WHERE id = NEW.order_item_id)
               - COALESCE((SELECT SUM(qty) FROM return_requests WHERE order_item_id = NEW.order_item_id AND status <> 'rejected'), 0)
BEGIN SELECT RAISE(ABORT,'Қайтару саны тапсырыстан артық'); END;

CREATE TRIGGER trg_return_transition BEFORE UPDATE OF status ON return_requests
WHEN NEW.status <> OLD.status
 AND NOT ((OLD.status='requested' AND NEW.status IN ('approved','rejected')) OR (OLD.status='approved' AND NEW.status='refunded'))
BEGIN SELECT RAISE(ABORT,'Қайтару мәртебесінің рұқсат етілмеген ауысуы'); END;

CREATE TRIGGER trg_return_refunded AFTER UPDATE OF status ON return_requests
WHEN NEW.status = 'refunded' AND OLD.status <> 'refunded'
BEGIN
  -- ақаулы тауар қоймаға қайтпайды, қалғандары қайтады
  INSERT INTO stock_movements(product_size_id, delta, reason, return_request_id)
  SELECT oi.product_size_id, NEW.qty, 'return', NEW.id
  FROM order_items oi WHERE oi.id = NEW.order_item_id AND NEW.reason_code <> 'defect';
  INSERT INTO notifications(user_id, kind, message, order_id)
  SELECT o.customer_id, 'return_status', 'Қайтару №' || NEW.id || ': ақша қайтарылды', o.id
  FROM order_items oi JOIN orders o ON o.id = oi.order_id WHERE oi.id = NEW.order_item_id;
END;

-- 8.8 Образ: тауардың слоты образдағы слотқа сәйкес болуы керек
CREATE TRIGGER trg_outfit_slot BEFORE INSERT ON outfit_items
WHEN (SELECT gt.slot FROM products p JOIN garment_types gt ON gt.code = p.garment_type WHERE p.id = NEW.product_id) IS NOT NEW.slot
BEGIN SELECT RAISE(ABORT,'Тауар түрі образ слотына сәйкес емес'); END;

-- ---------------------------------------------------------------------
-- 9. VIEW: отыру логикасы (3D манекеннің түстері мен өлшем ұсынысы)
-- ---------------------------------------------------------------------
-- Әр клиент × өлшем × аймақ үшін айырма мен үкім. Сан өлшемі денеден шамамен: жамбас × 0.56
CREATE VIEW v_fit_zones AS
WITH base AS (
  SELECT bp.user_id, bp.chest_cm AS b_chest, bp.waist_cm AS b_waist, bp.hip_cm AS b_hip,
         ps.id AS product_size_id, ps.product_id, ps.size_label, sl.rank AS size_rank,
         ps.chest_cm, ps.hem_cm, ps.waist_cm, ps.hip_cm, ps.thigh_cm, gt.slot
  FROM body_profiles bp
  CROSS JOIN product_sizes ps
  JOIN products p        ON p.id = ps.product_id
  JOIN garment_types gt  ON gt.code = p.garment_type
  JOIN size_labels sl    ON sl.label = ps.size_label
), z AS (
  SELECT user_id, product_size_id, product_id, size_label, size_rank, 'chest' AS zone, b_chest AS body_cm, chest_cm AS garment_cm FROM base WHERE slot='top'    AND chest_cm IS NOT NULL
  UNION ALL
  SELECT user_id, product_size_id, product_id, size_label, size_rank, 'hem',   b_hip,                   hem_cm   FROM base WHERE slot='top'    AND hem_cm   IS NOT NULL
  UNION ALL
  SELECT user_id, product_size_id, product_id, size_label, size_rank, 'waist', b_waist,                 waist_cm FROM base WHERE slot='bottom' AND waist_cm IS NOT NULL
  UNION ALL
  SELECT user_id, product_size_id, product_id, size_label, size_rank, 'hip',   b_hip,                   hip_cm   FROM base WHERE slot='bottom' AND hip_cm   IS NOT NULL
  UNION ALL
  SELECT user_id, product_size_id, product_id, size_label, size_rank, 'thigh', ROUND(b_hip*0.56,1),    thigh_cm FROM base WHERE slot='bottom' AND thigh_cm IS NOT NULL
)
SELECT z.user_id, z.product_size_id, z.product_id, z.size_label, z.size_rank, z.zone,
       z.body_cm, z.garment_cm,
       ROUND(z.garment_cm - z.body_cm, 1) AS diff_cm,
       CASE WHEN z.garment_cm - z.body_cm < r.tight_below THEN 'tight'
            WHEN z.garment_cm - z.body_cm > r.loose_above THEN 'loose'
            ELSE 'fit' END AS verdict
FROM z JOIN fit_rules r ON r.zone = z.zone;

-- Бір өлшемнің жалпы үкімі
CREATE VIEW v_size_verdict AS
SELECT user_id, product_size_id, product_id, size_label, size_rank,
       CASE WHEN SUM(verdict='tight') > 0 THEN 'tight'
            WHEN SUM(verdict='loose') > 0 THEN 'loose'
            ELSE 'fit' END AS verdict
FROM v_fit_zones
GROUP BY user_id, product_size_id;

-- Ұсынылатын өлшем: «қысатын» аймағы жоқ және қоймада бар ең кіші өлшем
CREATE VIEW v_recommended_size AS
SELECT user_id, product_id, product_size_id, size_label
FROM (
  SELECT v.user_id, v.product_id, v.product_size_id, v.size_label,
         ROW_NUMBER() OVER (PARTITION BY v.user_id, v.product_id ORDER BY v.size_rank) AS rn
  FROM v_size_verdict v
  JOIN product_sizes ps ON ps.id = v.product_size_id AND ps.stock_qty > 0
  WHERE v.verdict <> 'tight'
)
WHERE rn = 1;

-- ---------------------------------------------------------------------
-- 10. VIEW: сатушы/менеджер/әкімші панельдері мен есептер
-- ---------------------------------------------------------------------
CREATE VIEW v_catalog AS
SELECT p.id AS product_id, p.name, p.price, p.color_hex, p.pattern, p.print_kind, p.garment_type,
       c.name AS category, sp.shop_name,
       COALESCE((SELECT SUM(stock_qty) FROM product_sizes WHERE product_id = p.id), 0) AS total_stock,
       (SELECT group_concat(size_label, ',') FROM (SELECT ps.size_label FROM product_sizes ps JOIN size_labels sl ON sl.label = ps.size_label
                                                    WHERE ps.product_id = p.id AND ps.stock_qty > 0 ORDER BY sl.rank)) AS sizes_in_stock
FROM products p
LEFT JOIN categories c ON c.id = p.category_id
LEFT JOIN seller_profiles sp ON sp.user_id = p.seller_id
WHERE p.is_active = 1;

CREATE VIEW v_seller_orders AS          -- сатушы панелі: өз тауарының тапсырыстары
SELECT p.seller_id, o.id AS order_id, o.status, o.created_at, u.full_name AS customer,
       oi.product_name, ps.size_label, oi.qty, oi.unit_price, oi.qty * oi.unit_price AS line_total
FROM order_items oi
JOIN orders o          ON o.id = oi.order_id
JOIN users u           ON u.id = o.customer_id
JOIN product_sizes ps  ON ps.id = oi.product_size_id
JOIN products p        ON p.id = ps.product_id;

CREATE VIEW v_low_stock AS
SELECT p.seller_id, p.id AS product_id, p.name, ps.size_label, ps.stock_qty
FROM product_sizes ps JOIN products p ON p.id = ps.product_id
WHERE p.is_active = 1 AND ps.stock_qty <= 3;

CREATE VIEW v_return_stats AS           -- әкімші есебі: қай тауар көп қайтарылады және неге
SELECT p.id AS product_id, p.name,
       COALESCE((SELECT SUM(oi.qty) FROM order_items oi JOIN orders o ON o.id = oi.order_id AND o.status = 'delivered'
                 JOIN product_sizes ps ON ps.id = oi.product_size_id WHERE ps.product_id = p.id),0) AS units_delivered,
       COALESCE((SELECT SUM(rr.qty) FROM return_requests rr JOIN order_items oi ON oi.id = rr.order_item_id
                 JOIN product_sizes ps ON ps.id = oi.product_size_id
                 WHERE ps.product_id = p.id AND rr.status IN ('approved','refunded')),0) AS units_returned,
       COALESCE((SELECT SUM(rr.qty) FROM return_requests rr JOIN order_items oi ON oi.id = rr.order_item_id
                 JOIN product_sizes ps ON ps.id = oi.product_size_id
                 JOIN return_reasons rs ON rs.code = rr.reason_code
                 WHERE ps.product_id = p.id AND rr.status IN ('approved','refunded') AND rs.is_size_related = 1),0) AS size_related_returns
FROM products p;
