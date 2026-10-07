# Дерекқор логикасының тесті: python database/test_db.py
import sqlite3, sys
from pathlib import Path
HERE = Path(__file__).parent
db = sqlite3.connect(":memory:"); db.execute("PRAGMA foreign_keys=ON")
db.executescript(open(HERE / "schema.sql", encoding="utf-8").read()); db.executescript(open(HERE / "seed.sql", encoding="utf-8").read())
def q(sql,*a): return db.execute(sql,a).fetchall()
def expect_fail(sql,*a):
    try: db.execute(sql,a); print("  !!! FAIL: қате күтілген еді:",sql[:70]); sys.exit(1)
    except sqlite3.DatabaseError as e: print("  OK қате:",str(e)[:80])
ok=lambda c,m:(print("  OK",m) if c else (print("  !!! FAIL",m),sys.exit(1)))
print("Қалдық (журнал арқылы):",q("SELECT SUM(stock_qty) FROM product_sizes")[0][0], "= журнал", q("SELECT SUM(delta) FROM stock_movements")[0][0])
print("Q2 ұсыныс Данияр:",q("SELECT p.name,r.size_label FROM v_recommended_size r JOIN products p ON p.id=r.product_id WHERE r.user_id=6"))
print("Q2 ұсыныс Айгерім:",q("SELECT p.name,r.size_label FROM v_recommended_size r JOIN products p ON p.id=r.product_id WHERE r.user_id=5"))
print("Q3 отыру (Айгерім, свитер):",q("SELECT size_label,zone,diff_cm,verdict FROM v_fit_zones WHERE user_id=5 AND product_id=2 ORDER BY size_rank,zone"))

print("\n== Рөл шектеулері")
expect_fail("INSERT INTO products(seller_id,garment_type,name,price) VALUES (5,'tee','x',100)")
expect_fail("INSERT INTO body_profiles(user_id,height_cm,weight_kg,chest_cm,waist_cm,hip_cm) VALUES (3,170,60,90,70,95)")
expect_fail("INSERT INTO orders(customer_id,ship_city,ship_street,ship_house,ship_phone) VALUES (3,'a','b','c','d')")
print("== Өлшем кестесінің міндеттілігі")
expect_fail("INSERT INTO product_sizes(product_id,size_label,sku,chest_cm) VALUES (1,'XXL','TEE-W-XXL',130)")      # hem жоқ
expect_fail("INSERT INTO product_sizes(product_id,size_label,sku,waist_cm,hip_cm) VALUES (3,'XXL','SHO-K-XXL',110,126)")  # thigh жоқ
expect_fail("INSERT INTO product_sizes(product_id,size_label,sku) VALUES (5,'M','SNK-W-M')")                           # аяқ киімге киім өлшемі

print("\n== Тапсырыс: қалдық, сома, мәртебе")
sz=lambda sku:q("SELECT id,stock_qty FROM product_sizes WHERE sku=?",sku)[0]
db.execute("INSERT INTO orders(customer_id,address_id,ship_city,ship_street,ship_house,ship_phone,last_changed_by) VALUES (5,1,'Алматы','Абай даңғылы','10','+77010000005',5)")
oid=q("SELECT max(id) FROM orders")[0][0]
sid,st0=sz("SWE-B-M")
db.execute("INSERT INTO order_items(order_id,product_size_id,product_name,unit_price,qty) VALUES (?,?,?,?,2)",(oid,sid,'Көк свитер',19900))
ok(sz("SWE-B-M")[1]==st0-2,"қалдық 2-ге азайды")
ok(q("SELECT total_amount FROM orders WHERE id=?",oid)[0][0]==39800,"сома 39800")
expect_fail("INSERT INTO order_items(order_id,product_size_id,product_name,unit_price,qty) VALUES (?,?,?,?,99)",oid,sid,'x',100)
expect_fail("UPDATE order_items SET qty=1 WHERE order_id=?",oid)
expect_fail("DELETE FROM orders WHERE id=?",oid)
expect_fail("UPDATE orders SET status='delivered' WHERE id=?",oid)                  # new→delivered болмайды
db.execute("INSERT INTO payments(order_id,amount,method,status) VALUES (?,?, 'kaspi','paid')",(oid,20000))
ok(q("SELECT status FROM orders WHERE id=?",oid)[0][0]=='new',"жартылай төлем: мәртебе әлі new")
db.execute("INSERT INTO payments(order_id,amount,method,status) VALUES (?,?, 'kaspi','paid')",(oid,19800))
ok(q("SELECT status FROM orders WHERE id=?",oid)[0][0]=='paid',"толық төлемнен кейін paid")
for s in ('packed','shipped','delivered'): db.execute("UPDATE orders SET status=?,last_changed_by=2 WHERE id=?",(s,oid))
print("  тарих:",[r[0] for r in q("SELECT status FROM order_status_history WHERE order_id=? ORDER BY id",oid)])
print("  хабарламалар:",[r[0] for r in q("SELECT message FROM notifications WHERE user_id=5 ORDER BY id")])

print("\n== Қайтару")
iid=q("SELECT id FROM order_items WHERE order_id=?",oid)[0][0]
expect_fail("INSERT INTO return_requests(order_item_id,qty,reason_code) VALUES (?,3,'too_big')",iid)   # артық
db.execute("INSERT INTO return_requests(order_item_id,qty,reason_code) VALUES (?,1,'too_big')",(iid,))
rid=q("SELECT max(id) FROM return_requests")[0][0]
expect_fail("UPDATE return_requests SET status='refunded' WHERE id=?",rid)                           # requested→refunded болмайды
db.execute("UPDATE return_requests SET status='approved',handled_by=2 WHERE id=?",(rid,))
before=sz("SWE-B-M")[1]
db.execute("UPDATE return_requests SET status='refunded' WHERE id=?",(rid,))
ok(sz("SWE-B-M")[1]==before+1,"қайтарылған тауар қоймаға оралды")
pid=q("SELECT id FROM payments WHERE order_id=? LIMIT 1",oid)[0][0]
db.execute("INSERT INTO refunds(payment_id,return_request_id,amount) VALUES (?,?,19900)",(pid,rid))
print("  Q8 қайтару есебі:",q("SELECT name,units_delivered,units_returned,size_related_returns FROM v_return_stats WHERE units_delivered>0"))

print("\n== Бас тарту және қайта келу хабарламасы")
db.execute("INSERT INTO orders(customer_id,ship_city,ship_street,ship_house,ship_phone) VALUES (6,'Астана','Достық','5','+77010000006')")
o2=q("SELECT max(id) FROM orders")[0][0]; sid4,st4=sz("PAN-G-XL")
db.execute("INSERT INTO order_items(order_id,product_size_id,product_name,unit_price,qty) VALUES (?,?,?,?,?)",(o2,sid4,'Сұр шалбар',15900,st4))
ok(sz("PAN-G-XL")[1]==0,"барлық қалдық алынды")
db.execute("UPDATE orders SET status='cancelled' WHERE id=?",(o2,))
ok(sz("PAN-G-XL")[1]==st4,"бас тартқанда қалдық қайтты")
db.execute("INSERT INTO stock_movements(product_size_id,delta,reason) VALUES (?,-?, 'adjust')",(sid4,st4))
db.execute("INSERT INTO stock_movements(product_size_id,delta,reason) VALUES (?,2,'restock')",(sid4,))
print("  қайта келу хабары:",q("SELECT user_id,message FROM notifications WHERE kind='back_in_stock'"))

print("\n== Образ")
db.execute("INSERT INTO outfits(id,user_id,name) VALUES (1,5,'Жазғы')")
db.execute("INSERT INTO outfit_items(outfit_id,slot,product_id,size_label) VALUES (1,'top',1,'M')")
expect_fail("INSERT INTO outfit_items(outfit_id,slot,product_id) VALUES (1,'bottom',1)")             # футболканы төменгі слотқа қоюға болмайды
print("\nБАРЛЫҒЫ ӨТТІ. Кестелер:",q("SELECT count(*) FROM sqlite_master WHERE type='table'")[0][0],"триггер:",q("SELECT count(*) FROM sqlite_master WHERE type='trigger'")[0][0],"view:",q("SELECT count(*) FROM sqlite_master WHERE type='view'")[0][0])
print("integrity:",q("PRAGMA integrity_check")[0][0],"fk:",q("PRAGMA foreign_key_check"))
