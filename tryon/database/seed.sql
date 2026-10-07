-- TryOn: тест деректері (демо). Парольдер — жалған хэштер.
PRAGMA foreign_keys = ON;

INSERT INTO roles(id,code,name) VALUES (1,'client','Клиент'),(2,'seller','Сатушы'),(3,'manager','Менеджер'),(4,'admin','Әкімші');

INSERT INTO garment_types(code,name,slot) VALUES
 ('tee','Футболка','top'),('sweater','Свитер','top'),('shorts','Шорты','bottom'),('pants','Шалбар','bottom'),('sneakers','Кроссовка','shoes');

INSERT INTO size_labels(label,rank,kind) VALUES
 ('XS',1,'clothes'),('S',2,'clothes'),('M',3,'clothes'),('L',4,'clothes'),('XL',5,'clothes'),('XXL',6,'clothes'),
 ('38',20,'shoes'),('39',21,'shoes'),('40',22,'shoes'),('41',23,'shoes'),('42',24,'shoes'),('43',25,'shoes'),('44',26,'shoes'),('45',27,'shoes'),('46',28,'shoes');

INSERT INTO order_statuses(code,name,sort_order) VALUES
 ('new','Қабылданды',1),('paid','Төленді',2),('packed','Жиналды',3),('shipped','Жолда',4),('delivered','Жеткізілді',5),('cancelled','Бас тартылды',9);
INSERT INTO order_transitions(from_status,to_status) VALUES
 ('new','paid'),('new','cancelled'),('paid','packed'),('paid','cancelled'),('packed','shipped'),('packed','cancelled'),('shipped','delivered');

INSERT INTO return_reasons(code,name,is_size_related) VALUES
 ('too_small','Өлшемі кіші',1),('too_big','Өлшемі үлкен',1),('defect','Ақаулы',0),('not_as_shown','Суреттегідей емес',0),('changed_mind','Ойымнан шықты',0);

INSERT INTO fit_rules(zone,tight_below,loose_above) VALUES
 ('chest',2,10),('hem',2,10),('waist',2,10),('hip',2,10),('thigh',1,10);

INSERT INTO categories(id,name,slug,parent_id) VALUES
 (1,'Жоғарғы киім','tops',NULL),(2,'Футболкалар','t-shirts',1),(3,'Свитерлер','sweaters',1),
 (4,'Төменгі киім','bottoms',NULL),(5,'Шортылар','shorts',4),(6,'Шалбарлар','pants',4),(7,'Аяқ киім','shoes',NULL);

INSERT INTO users(id,email,password_hash,full_name,phone,role_id) VALUES
 (1,'admin@tryon.kz','hash_demo','Әкімші','+77000000001',4),
 (2,'manager@tryon.kz','hash_demo','Менеджер Асхат','+77000000002',3),
 (3,'seller1@tryon.kz','hash_demo','Сатушы Нұрлан','+77000000003',2),
 (4,'seller2@tryon.kz','hash_demo','Сатушы Меруерт','+77000000004',2),
 (5,'aigerim@example.com','hash_demo','Айгерім','+77010000005',1),
 (6,'daniyar@example.com','hash_demo','Данияр','+77010000006',1),
 (7,'aliya@example.com','hash_demo','Әлия','+77010000007',1);
INSERT INTO seller_profiles(user_id,shop_name,is_verified) VALUES (3,'UrbanWear',1),(4,'Basic Studio',1);

INSERT INTO body_profiles(user_id,sex,height_cm,weight_kg,chest_cm,waist_cm,hip_cm,measures_source) VALUES
 (5,'f',165,58,87,70,100,'estimated'),
 (6,'m',182,95,112,96,113,'estimated'),
 (7,'f',170,62,90,72,98,'manual');
INSERT INTO addresses(id,user_id,label,city,street,house,apartment,recipient_phone,is_default) VALUES
 (1,5,'Үй','Алматы','Абай даңғылы','10','25','+77010000005',1),
 (2,6,'Үй','Астана','Достық көшесі','5',NULL,'+77010000006',1);

INSERT INTO products(id,seller_id,category_id,garment_type,name,description,price,color_hex,pattern,print_kind) VALUES
 (1,3,2,'tee','Ақ футболка TryOn',        'Мақта, түзу пішін',          8900,'#f4f1ea','solid','logo'),
 (2,3,3,'sweater','Көк свитер',            'Жылы, манжеттері бар',       19900,'#2f5d8a','solid',NULL),
 (3,4,5,'shorts','Қара шорты',             'Жеңіл, спорт',               9900,'#1f2430','solid',NULL),
 (4,4,6,'pants','Сұр шалбар',              'Түзу пішін',                 15900,'#8c8c8c','solid',NULL),
 (5,3,7,'sneakers','Ақ кроссовка',         'Күнделікті',                 24900,'#f4f1ea','solid',NULL),
 (6,4,2,'tee','Жолақты футболка',          'Көк-ақ жолақ',               9500,'#2f5d8a','stripe',NULL);
INSERT INTO product_images(product_id,path,kind) VALUES (1,'img/tee_white.jpg','photo'),(1,'img/logo_tryon.png','print'),(2,'img/sweater_blue.jpg','photo');

-- Өлшем кестелері (киім өлшемдері, см). Топ: кеуде/етек. Төменгі: бел/жамбас/сан.
INSERT INTO product_sizes(product_id,size_label,sku,chest_cm,hem_cm,waist_cm,hip_cm,thigh_cm) VALUES
 (1,'S','TEE-W-S',98,98,NULL,NULL,NULL),(1,'M','TEE-W-M',106,106,NULL,NULL,NULL),(1,'L','TEE-W-L',114,114,NULL,NULL,NULL),(1,'XL','TEE-W-XL',122,122,NULL,NULL,NULL),
 (2,'S','SWE-B-S',102,96,NULL,NULL,NULL),(2,'M','SWE-B-M',110,104,NULL,NULL,NULL),(2,'L','SWE-B-L',118,112,NULL,NULL,NULL),(2,'XL','SWE-B-XL',126,120,NULL,NULL,NULL),
 (3,'S','SHO-K-S',NULL,NULL,82,98,58),(3,'M','SHO-K-M',NULL,NULL,90,106,62),(3,'L','SHO-K-L',NULL,NULL,98,114,67),(3,'XL','SHO-K-XL',NULL,NULL,106,122,72),
 (4,'S','PAN-G-S',NULL,NULL,82,98,59),(4,'M','PAN-G-M',NULL,NULL,90,106,64),(4,'L','PAN-G-L',NULL,NULL,98,114,69),(4,'XL','PAN-G-XL',NULL,NULL,106,122,74),
 (5,'40','SNK-W-40',NULL,NULL,NULL,NULL,NULL),(5,'42','SNK-W-42',NULL,NULL,NULL,NULL,NULL),(5,'44','SNK-W-44',NULL,NULL,NULL,NULL,NULL),
 (6,'S','TEE-S-S',98,98,NULL,NULL,NULL),(6,'M','TEE-S-M',106,106,NULL,NULL,NULL),(6,'L','TEE-S-L',114,114,NULL,NULL,NULL);

-- Бастапқы қалдық: журнал арқылы (stock_qty өзі өзгермейді)
INSERT INTO stock_movements(product_size_id,delta,reason,created_by)
SELECT id, CASE size_label WHEN 'S' THEN 2 WHEN 'M' THEN 5 WHEN 'L' THEN 4 WHEN 'XL' THEN 1 ELSE 3 END, 'restock', product_id_seller
FROM (SELECT ps.id, ps.size_label, p.seller_id AS product_id_seller FROM product_sizes ps JOIN products p ON p.id = ps.product_id);

INSERT INTO favorites(user_id,product_id) VALUES (5,2),(6,4);
INSERT INTO cart_items(user_id,product_size_id,qty) VALUES (7,(SELECT id FROM product_sizes WHERE sku='TEE-S-M'),1);
