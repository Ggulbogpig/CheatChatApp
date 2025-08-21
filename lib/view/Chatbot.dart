import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../view/main/detail/chat_page1.dart';

//final googleAI = FirebaseAI.googleAI(auth:FirebaseAuth.instance);
// final model = googleAI.generativeModel(model: 'gemeni-2.0-flash',
// generationConfig: GenerationConfig(
//   maxOutputTokens: 8192,
//   responseMimeType: 'text/plain'
// ),);
//
// late ChatSession _chat;     // 제미니 채팅 세션
// bool _chatReady = false;
//
// Future<void> _initAiCoach({
//   required String relation,      // 두 사람 관계
//   required String style,         // 사용자의 말투/스타일(예: “존댓말, 부드럽게”)
//   int limit = 40,                // 히스토리는 최신 N개만
// }) async {
//   // 1) 모델 준비
//   final model = googleAI.generativeModel(
//     // 프로젝트에 따라 'gemini-2.0-flash' 또는 'gemini-2.5-flash'
//     model: 'gemini-2.0-flash',
//     systemInstruction: Content.system(
//         '너는 두 사람의 대화를 보고, 사용자의 "$style" 말투를 반영해 '
//             '상대가 방금 보낸 메시지에 대한 답장 후보 2~3개만 제안하는 코치야. '
//             '대화는 "ME:"(사용자)와 "PARTNER:"(상대) 태그로 구분돼. '
//             '두 사람의 관계: $relation. '
//             '각 답변은 1~2문장으로 자연스럽게.'
//     ),
//     generationConfig: const GenerationConfig(
//       maxOutputTokens: 8192,
//       responseMimeType: 'text/plain',
//     ),
//   );
//
//   // 2) Firestore에서 과거 로그 불러오기 (오래된 -> 최신)
//   final qs = await _firebase
//       .collection('messages')
//       .doc(widget.selectedPost.id)
//       .collection('chat')
//       .orderBy('timestamp', descending: false)
//       .limit(limit)
//       .get();
//
//   final history = <Content>[];
//   for (final d in qs.docs) {
//     final m = d.data() as Map<String, dynamic>;
//     final who = (m['user'] == user.email) ? 'ME' : 'PARTNER';
//     final text = (m['comment'] ?? '').toString();
//     if (text.isEmpty) continue;
//     // 히스토리는 모두 role='user'로 두고, 본문에 태그로 화자를 구분
//     history.add(Content('user', [TextPart('$who: $text')]));
//   }
//
//   // 3) 히스토리를 넣고 세션 시작
//   _chat = model.startChat(history: history);
//   _chatReady = true;
// }
