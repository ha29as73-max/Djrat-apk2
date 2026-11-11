// دجرات - تطبيق أندرويد (المرحلة 1): تسجيل الدخول، المحادثات، الرسائل المباشرة.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://bxztqgnjffnhlabdwjro.supabase.co';
const supabaseKey = 'sb_publishable_m8CfMRG3NOB9OPc9TPH-uQ_8xwhGTGx';
const teal = Color(0xFF088395);

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const DjratApp());
}

String uuid4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String bodyText(Map<String, dynamic> m) {
  if (m['deleted_all'] == true) return '🚫 تم حذف هذه الرسالة';
  final b = (m['body'] ?? '') as String;
  if (b.startsWith('⟦e2e⟧')) return '🔒 رسالة مشفّرة';
  if (b.startsWith('⟦poll⟧')) return '📊 استطلاع';
  switch (m['kind']) {
    case 'image': return '📷 صورة';
    case 'video': return '🎥 فيديو';
    case 'audio': return '🎤 رسالة صوتية';
    case 'file': return '📎 ملف';
    case 'location': return '📍 موقع';
  }
  return b;
}

String hhmm(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class DjratApp extends StatelessWidget {
  const DjratApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دجرات',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: teal), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.dark), useMaterial3: true),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const Gate(),
    );
  }
}

/// يقرر: تسجيل دخول / إعداد الملف / الرئيسية
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  StreamSubscription<AuthState>? _sub;
  @override
  void initState() {
    super.initState();
    _sub = db.auth.onAuthStateChange.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = db.auth.currentUser;
    if (user == null) return const LoginPage();
    return ProfileGate(key: ValueKey(user.id), uid: user.id);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final code = TextEditingController();
  bool sent = false, busy = false;
  String? err;

  Future<void> run(Future<void> Function() f) async {
    setState(() { busy = true; err = null; });
    try { await f(); } catch (e) { err = 'تعذّر: $e'; }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chat_bubble_rounded, size: 72, color: teal),
              const SizedBox(height: 8),
              const Text('دجرات', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: teal)),
              const SizedBox(height: 28),
              TextField(
                controller: email,
                enabled: !sent,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder()),
              ),
              if (sent) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'رمز التحقق المرسل لبريدك', border: OutlineInputBorder()),
                ),
              ],
              if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            if (!sent) {
                              await db.auth.signInWithOtp(email: email.text.trim(), shouldCreateUser: true);
                              sent = true;
                            } else {
                              await db.auth.verifyOtp(email: email.text.trim(), token: code.text.trim(), type: OtpType.email);
                            }
                          }),
                  child: Padding(padding: const EdgeInsets.all(12), child: Text(sent ? 'دخول' : 'إرسال الرمز')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class ProfileGate extends StatefulWidget {
  final String uid;
  const ProfileGate({super.key, required this.uid});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  Map<String, dynamic>? me;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await db.from('profiles').select().eq('id', widget.uid).maybeSingle();
    if (mounted) setState(() { me = r; loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (me == null) return SetupPage(uid: widget.uid, onDone: load);
    return HomePage(me: me!);
  }
}

class SetupPage extends StatefulWidget {
  final String uid;
  final Future<void> Function() onDone;
  const SetupPage({super.key, required this.uid, required this.onDone});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final name = TextEditingController();
  final user = TextEditingController();
  String? err;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد الملف الشخصي')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: user, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'اسم المستخدم (إنجليزي)', border: OutlineInputBorder())),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() { busy = true; err = null; });
                    try {
                      await db.from('profiles').insert({'id': widget.uid, 'name': name.text.trim(), 'username': user.text.trim().toLowerCase()});
                      await widget.onDone();
                    } catch (e) {
                      err = 'تعذّر الحفظ (قد يكون اسم المستخدم مأخوذاً): $e';
                    }
                    if (mounted) setState(() => busy = false);
                  },
            child: const Padding(padding: EdgeInsets.all(12), child: Text('حفظ ومتابعة')),
          ),
        ]),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final Map<String, dynamic> me;
  const HomePage({super.key, required this.me});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, Map<String, dynamic>> people = {};
  Map<String, Map<String, dynamic>> last = {};
  bool loading = true;
  RealtimeChannel? ch;
  String get myId => widget.me['id'] as String;

  @override
  void initState() {
    super.initState();
    load();
    ch = db
        .channel('home-$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (ch != null) db.removeChannel(ch!);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final cs = await db.from('contacts').select('contact').eq('owner', myId);
      final ids = <String>{for (final c in cs) c['contact'] as String};
      final ms = await db
          .from('messages')
          .select()
          .or('sender.eq.$myId,recipient.eq.$myId')
          .order('created_at', ascending: false)
          .limit(400);
      final lastMap = <String, Map<String, dynamic>>{};
      for (final m in ms) {
        final peer = (m['sender'] == myId ? m['recipient'] : m['sender']) as String;
        ids.add(peer);
        lastMap.putIfAbsent(peer, () => m);
      }
      final ps = ids.isEmpty ? [] : await db.from('profiles').select().inFilter('id', ids.toList());
      if (!mounted) return;
      setState(() {
        people = {for (final p in ps) p['id'] as String: p};
        last = lastMap;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = people.keys.toList()
      ..sort((a, b) => ((last[b]?['created_at'] ?? '') as String).compareTo((last[a]?['created_at'] ?? '') as String));
    return Scaffold(
      appBar: AppBar(
        title: const Text('دجرات', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'تسجيل الخروج', onPressed: () => db.auth.signOut()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => AddContactPage(myId: myId)));
          load();
        },
        child: const Icon(Icons.person_add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : order.isEmpty
              ? const Center(child: Text('لا توجد محادثات بعد.\nاضغط الزر لإضافة جهة اتصال.', textAlign: TextAlign.center))
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView.separated(
                    itemCount: order.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = people[order[i]]!;
                      final m = last[order[i]];
                      final nm = (p['name'] ?? p['username'] ?? '') as String;
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: teal, foregroundColor: Colors.white, child: Text(nm.isEmpty ? '?' : nm.characters.first)),
                        title: Text(nm, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(m == null ? '' : bodyText(m), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(hhmm(m?['created_at'] as String?), style: const TextStyle(fontSize: 11)),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(myId: myId, peer: p)));
                          load();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class AddContactPage extends StatefulWidget {
  final String myId;
  const AddContactPage({super.key, required this.myId});
  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage> {
  final q = TextEditingController();
  String? msg;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة جهة اتصال')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: q, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () async {
              final u = q.text.trim().toLowerCase().replaceAll('@', '');
              final r = await db.from('profiles').select().eq('username', u).maybeSingle();
              if (r == null) {
                setState(() => msg = 'لم يُعثر على هذا المستخدم');
                return;
              }
              if (r['id'] == widget.myId) {
                setState(() => msg = 'هذا حسابك');
                return;
              }
              try {
                await db.from('contacts').upsert({'owner': widget.myId, 'contact': r['id']});
              } catch (_) {}
              if (!mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatPage(myId: widget.myId, peer: r)));
            },
            child: const Padding(padding: EdgeInsets.all(10), child: Text('بحث وفتح المحادثة')),
          ),
          if (msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(msg!)),
        ]),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String myId;
  final Map<String, dynamic> peer;
  const ChatPage({super.key, required this.myId, required this.peer});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Map<String, dynamic>> msgs = [];
  RealtimeChannel? ch;
  String get peerId => widget.peer['id'] as String;

  @override
  void initState() {
    super.initState();
    load();
    ch = db
        .channel('chat-${widget.myId}-$peerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) {
            final m = p.newRecord;
            final mine = m['sender'] == widget.myId && m['recipient'] == peerId;
            final theirs = m['sender'] == peerId && m['recipient'] == widget.myId;
            if ((mine || theirs) && !msgs.any((x) => x['id'] == m['id'])) {
              setState(() => msgs.add(m));
              toEnd();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (ch != null) db.removeChannel(ch!);
    super.dispose();
  }

  void toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> load() async {
    final me = widget.myId;
    final r = await db
        .from('messages')
        .select()
        .or('and(sender.eq.$me,recipient.eq.$peerId),and(sender.eq.$peerId,recipient.eq.$me)')
        .order('created_at', ascending: true)
        .limit(300);
    if (!mounted) return;
    setState(() => msgs = List<Map<String, dynamic>>.from(r));
    toEnd();
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    final row = {'id': uuid4(), 'sender': widget.myId, 'recipient': peerId, 'kind': 'text', 'body': t};
    setState(() => msgs.add({...row, 'created_at': DateTime.now().toUtc().toIso8601String()}));
    toEnd();
    try {
      await db.from('messages').insert(row);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الإرسال: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = (widget.peer['name'] ?? widget.peer['username'] ?? '') as String;
    return Scaffold(
      appBar: AppBar(title: Text(nm)),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(10),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[i];
              final mine = m['sender'] == widget.myId;
              final cs = Theme.of(context).colorScheme;
              return Align(
                alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  decoration: BoxDecoration(
                    color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bodyText(m)),
                    const SizedBox(height: 2),
                    Text(hhmm(m['created_at'] as String?), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: 'اكتب رسالة', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
