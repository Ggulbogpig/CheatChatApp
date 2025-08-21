import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:first_flutter_app/data/item_data.dart';
import 'package:first_flutter_app/data/user.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async'; // <-- 추가
import 'dart:convert'; // JSON 파싱용



final googleAI = FirebaseAI.googleAI(auth:FirebaseAuth.instance);

class ChatPage extends StatefulWidget {
  final ItemData selectedPost;

  const ChatPage({super.key, required this.selectedPost});

  @override
  State<StatefulWidget> createState() {
    return _ChatPage();
  }
}

class _ChatPage extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();

  final ChatUser user = Get.find();
  final _firebase = FirebaseFirestore.instance;

  String _relation = '친한 친구';
  String _style    = '반말, 편하게';

  // 중복/순서 가드용
  String? _lastSuggestedMsgId;   // 마지막으로 '후보 생성'을 수행한 문서 id
  bool _isGenerating = false;    // 후보 생성 중 재진입 방지

// (테스트용) 내가 보낸 메시지에도 후보를 만들지 여부
  static const bool kSuggestOnlyOnPartner = false; // 테스트 시 false 로

  //String? _lastSuggestedMsgId;   // 마지막으로 제안한 메시지 id
  bool _bootstrapped = false;    // 첫 스냅샷(기존 로그) 스킵 여부

  Future<void> _openAiConfigSheet() async {
    final relations = ['친한 친구', '연인', '동료', '가족', '직장', '기타'];
    final styles    = ['반말, 편하게', '존댓말, 부드럽게', '밝고 활기차게', '차분하고 간결하게'];

    String tempRelation = _relation;
    String tempStyle    = _style;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setM) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('두 사람의 관계', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempRelation,
                  items: relations
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setM(() => tempRelation = v ?? tempRelation),
                ),
                const SizedBox(height: 16),
                const Text('사용자 말투/스타일', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: styles.map((s) => ChoiceChip(
                    label: Text(s),
                    selected: tempStyle == s,
                    onSelected: (_) => setM(() => tempStyle = s),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop({'relation': tempRelation, 'style': tempStyle});
                    },
                    child: const Text('적용하기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return; // 취소
    await _rebuildAiCoach(relation: result['relation']!, style: result['style']!);
  }

  Future<void> _rebuildAiCoach({required String relation, required String style}) async {
    // 기존 세션 정지 후 재생성
    _chatReady = false;
    setState(() {
      _relation = relation;
      _style = style;
      _suggestions.clear();        // 이전 제안 초기화(선택)
    });
    await _initAiCoach(relation: relation, style: style); // 아래 3) 참고
  }



  void _handleSubmitted(String text) {
    _textController.clear();
    _firebase
        .collection('messages')
        .doc(widget.selectedPost.id)
        .set({'timestamp': FieldValue.serverTimestamp()}).then((value) {
      _firebase
          .collection('messages')
          .doc(widget.selectedPost.id)
          .collection('chat')
          .add({
        'user': user.email,
        'comment': text,
        'timestamp': FieldValue.serverTimestamp()
      });
    });
  }

  // final model = googleAI.generativeModel(model: 'gemini-2.0-flash',
  //   generationConfig: GenerationConfig(
  //       maxOutputTokens: 8192,
  //       responseMimeType: 'text/plain'
  //   ),);

  late ChatSession _chat; // 제미니 채팅 세션
  bool _chatReady = false;

  Future<void> _initAiCoach({
    required String relation, // 두 사람 관계
    required String style, // 사용자의 말투/스타일(예: “존댓말, 부드럽게”)
    int limit = 40, // 히스토리는 최신 N개만
  }) async {
    // 1) 모델 준비
    final model = googleAI.generativeModel(
      // 프로젝트에 따라 'gemini-2.0-flash' 또는 'gemini-2.5-flash'
      model: 'gemini-2.0-flash',
      systemInstruction: Content.system(
          '너는 두 사람의 대화를 보고, 사용자의 "$style" 말투를 반영해 '
              '상대가 방금 보낸 메시지에 대한 답장 후보 2~3개만 제안하는 코치야. '
              '대화는 "ME:"(사용자)와 "PARTNER:"(상대) 태그로 구분돼. '
              '두 사람의 관계: $relation. '
              '각 답변은 1~2문장으로 자연스럽게.'
      ),
      generationConfig: GenerationConfig(
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',
      ),
    );

    // 2) Firestore에서 과거 로그 불러오기 (오래된 -> 최신)
    final qs = await _firebase
        .collection('messages')
        .doc(widget.selectedPost.id)
        .collection('chat')
        .orderBy('timestamp', descending: false)
        .limit(limit)
        .get();

    final history = <Content>[];
    for (final d in qs.docs) {
      final m = d.data() as Map<String, dynamic>;
      final who = (m['user'] == user.email) ? 'ME' : 'PARTNER';
      final text = (m['comment'] ?? '').toString();
      if (text.isEmpty) continue;
      // 히스토리는 모두 role='user'로 두고, 본문에 태그로 화자를 구분
      history.add(Content('user', [TextPart('$who: $text')]));
    }

    // 3) 히스토리를 넣고 세션 시작
    _chat = model.startChat(history: history);
    _chatReady = true;
  }


  Future<List<String>> _makeSuggestions() async {
    // 1) JSON 시도
    final promptJson =
        '위 흐름을 반영해 ME가 보낼 답장 후보 3개를 JSON으로만 반환:\n'
        '{ "candidates": [ {"text": "..."}, {"text": "..."}, {"text": "..."} ] }';

    try {
      final resp = await _chat.sendMessage(Content.text(promptJson));
      debugPrint('[AI] raw JSON text: "${resp.text}"');
      final map = jsonDecode(resp.text ?? '{}') as Map<String, dynamic>;
      final raw = (map['candidates'] as List?) ?? const [];
      final list = raw
          .map((e) => (e as Map)['text']?.toString() ?? '')
          .where((s) =>
      s
          .trim()
          .isNotEmpty)
          .take(3)
          .cast<String>()
          .toList();
      if (list.isNotEmpty) return list;
    } catch (e, st) {
      debugPrint('[AI] JSON parse error: $e\n$st');
    }

    // 2) 구분자 폴백 (||| 로 구분)
    final promptDelim =
        '위 흐름을 반영해 ME가 보낼 답장 후보 3개를 만들어줘. '
        '각 후보 사이를 "|||" 로 구분하고, 다른 출력은 하지 마.';
    try {
      final resp2 = await _chat.sendMessage(Content.text(promptDelim));
      final raw = (resp2.text ?? '').trim();
      debugPrint('[AI] raw delim text: "$raw"');
      final list = raw
          .split('|||')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(3)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (e, st) {
      debugPrint('[AI] delim parse error: $e\n$st');
    }

    // 3) 줄바꿈 폴백
    final promptLines =
        '위 흐름을 반영해 ME가 보낼 답장 후보 3개를 한 줄에 하나씩 출력해줘. 다른 말은 하지마.';
    try {
      final resp3 = await _chat.sendMessage(Content.text(promptLines));
      final raw = (resp3.text ?? '').trim();
      debugPrint('[AI] raw line text: "$raw"');
      final list = raw
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.replaceAll(RegExp(r'^[-•]\s*'), '').trim())
          .where((s) => s.isNotEmpty)
          .take(3)
          .toList();
      return list;
    } catch (e, st) {
      debugPrint('[AI] line parse error: $e\n$st');
    }

    return const [];
  }


  @override
  void initState() {
    super.initState();
    _init(); // 비동기 분리
  }

  //StreamSubscription<QuerySnapshot>? _sub;



  // 멤버들
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;




  Future<void> _init() async {
    //super.initState();
    // AI 세션 초기화 (원하는 시점에 relation/style 세팅)
    await _initAiCoach(relation: _relation, style: _style);

    _bootstrapped = false;
    // 새 문서가 추가될 때마다 후처리
    _sub = _firebase
        .collection('messages')
        .doc(widget.selectedPost.id)
        .collection('chat')
        .orderBy('timestamp')
        .snapshots()
        .listen(_onSnapshot);
  }

  List<String> _suggestions = [];

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    if (!_chatReady || snap.docChanges.isEmpty) return;

    // 이번 배치에서 가장 마지막 PARTNER 문서만 타겟팅
    DocumentSnapshot<Map<String, dynamic>>? lastPartner;

    // (1) 모든 새 메시지를 히스토리에 반영
    for (final ch in snap.docChanges) {
      if (ch.type != DocumentChangeType.added) continue;

      final data = ch.doc.data();
      if (data == null) continue;

      final msgText = (data['comment'] ?? '').toString().trim();
      final sender  = (data['user'] ?? '').toString();
      final role    = (data['role'] ?? 'user').toString();
      if (msgText.isEmpty) continue;
      if (role == 'assistant') continue; // 루프 방지

      final isPartner = sender != user.email;
      final tag = isPartner ? 'PARTNER' : 'ME';

      try {
        await _chat.sendMessage(Content.text('$tag: $msgText'));
      } catch (e, st) {
        debugPrint('[AI] history send error: $e\n$st');
      }

      if (isPartner) {
        lastPartner = ch.doc; // 계속 덮어써서 마지막 PARTNER만 남김
      }
    }

    // (2) 테스트 중이면 ME에도 후보 생성 허용
    if (lastPartner == null && !kSuggestOnlyOnPartner) {
      // 배치에 PARTNER가 없었지만, 마지막 변경(가장 뒤)에 대해 생성해보기
      final added = snap.docChanges
          .where((c) => c.type == DocumentChangeType.added)
          .toList();
      if (added.isNotEmpty) {
        lastPartner = added.last.doc; // 마지막 추가 문서 기준(테스트용)
      }
    }

    if (lastPartner == null) return;

    // (3) 같은 문서에 대해 중복 생성 방지
    if (_lastSuggestedMsgId == lastPartner!.id) {
      debugPrint('[AI] skip (already suggested for ${lastPartner!.id})');
      return;
    }

    if (_isGenerating) {
      debugPrint('[AI] skip (busy)');
      return;
    }
    _isGenerating = true;

    // (4) 후보 3개 생성
    final candidates = await _makeSuggestions();
    _isGenerating = false;

    if (!mounted) return;
    setState(() {
      _lastSuggestedMsgId = lastPartner!.id;
      _suggestions = candidates;          // UI에 한 번만 표시
    });

    debugPrint('[AI] suggestions => ${candidates.length}: $candidates');
  }




  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('채팅'),
        actions: [
          // AI 설정 시트 열기 (relation/style 선택)
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'AI 설정',
            onPressed: _openAiConfigSheet, // ← State 클래스에 만든 함수
          ),
          // (옵션) 현재 떠있는 제안 칩 모두 비우기
          if (_suggestions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: '제안 비우기',
              onPressed: () => setState(() => _suggestions.clear()),
            ),
        ],),
      body: Column(
        children: [
          // 1) 제안 칩 (사용자가 눌러야 전송)
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestions.map((s) {
                  return ActionChip(
                    label: Text(
                        s, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onPressed: () {
                      _handleSubmitted(s); // 클릭 시에만 전송
                      setState(() => _suggestions.clear()); // 전송 뒤 비우기
                    },
                  );
                }).toList(),
              ),
            ),

          // 2) 메시지 리스트
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firebase
                  .collection('messages')
                  .doc(widget.selectedPost.id)
                  .collection('chat')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('에러발생'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('데이터가 없습니다 첫글을 써보세요'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data(); // Map<String, dynamic>
                    final isMe = (data['user'] ?? '') == user.email;
                    final text = (data['comment'] ?? '').toString();

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment
                          .centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.lightBlueAccent : Colors
                              .grey[300],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(height: 1),

          // 3) 입력창
          Container(
            color: Theme
                .of(context)
                .cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onSubmitted: _handleSubmitted,
                    decoration: const InputDecoration.collapsed(
                      hintText: '메시지를 입력하세요',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _handleSubmitted(_textController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}
