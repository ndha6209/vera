# Vera Cloud — المنصة التعليمية السحابية

نظام عربي RTL لإدارة مؤسسة تعليمية متعددة المستخدمين، بواجهة GitHub Pages وقاعدة بيانات Supabase PostgreSQL ومصادقة Supabase Auth.

## محتويات المستودع
- `index.html`: واجهة Vera Cloud.
- `config.js`: إعداد الاتصال العام بمشروع Supabase.
- `supabase/schema.sql`: الجداول، الأدوار، سياسات RLS، وسجل التدقيق.
- `IMG-20261121-WA0003.jpg`: شعار Vera.

## الإعداد الإلزامي قبل الاستخدام
1. أنشئ مشروعاً جديداً في https://supabase.com/.
2. افتح SQL Editor في مشروع Supabase والصق ملف `supabase/schema.sql` كاملاً وشغّله مرة واحدة على قاعدة فارغة.
3. افتح Project Settings → API وانسخ Project URL و anon/publishable key.
4. افتح `config.js` في GitHub واضغط Edit، واستبدل القيمتين:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   استخدم المفتاح العام anon/publishable فقط. لا تضع service_role key أبداً.
5. افتح Supabase → Authentication → URL Configuration وأضف رابط GitHub Pages إلى Site URL و Redirect URLs.
6. أنشئ حسابك من صفحة Vera. سيُنشأ ملف profile تلقائياً بدور student.
7. من Supabase → Authentication → Users انسخ UUID الخاص بحسابك، ثم نفّذ في SQL Editor:
   `update public.profiles set role='admin' where id='ضع-UUID-هنا';`
8. سجّل الخروج ثم الدخول مجدداً. أصبح حسابك مدير النظام.

## ربط ملف الطالب بحسابه
بعد إنشاء حساب طالب، أنشئ سجله في جدول students واجعل عمود `auth_user_id` مساوياً لمعرّف حسابه في Auth. لا تستخدم مطابقة الأسماء لربط الحسابات.

## النشر
المستودع الحالي: https://github.com/ndha6209/vera
رابط الموقع: https://ndha6209.github.io/vera/
في GitHub: Settings → Pages → Deploy from a branch → main → /(root).

## الوظائف الموجودة في الواجهة
لوحة إحصاءات، دخول وإنشاء حساب، صلاحيات بحسب الدور، إدارة الطلاب والمدرسين والدورات والتسجيلات والحضور والاختبارات والفواتير والمدفوعات والمصروفات والإعلانات، إدارة أدوار المستخدمين للمدير، وسجل تدقيق.

## حدود النسخة الحالية
هذه هي البنية السحابية الأولى وليست اعتماداً إنتاجياً نهائياً. يلزم إعداد مشروع Supabase ومراجعة سياسات RLS واختبار كل دور. محرر الأسئلة ومحرك الاختبارات المؤقت والتصحيح الآلي وإدارة المستندات والشهادات والتقارير المتقدمة وتكاملات الدفع والإشعارات تحتاج مراحل تنفيذ إضافية. لا تدخل بيانات حقيقية قبل إكمال الاختبارات الأمنية والتشغيلية.
