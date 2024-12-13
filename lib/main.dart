import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoginScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatRoomId;

  ChatScreen({required this.chatRoomId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  // 参加者の追加画面への遷移
  void _addParticipants() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddParticipantsScreen(chatRoomId: widget.chatRoomId),
      ),
    );
  }

  Future<void> _showParticipants() async {
  final chatRoomSnapshot = await FirebaseFirestore.instance
      .collection('chat_rooms')
      .doc(widget.chatRoomId)
      .get();

  final chatRoomData = chatRoomSnapshot.data();
  if (chatRoomData != null) {
    final participants = List<String>.from(chatRoomData['participants'] ?? []);
    print('Participants List: $participants');

    // 参加者ごとにデータを取得
    for (var participantId in participants) {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(participantId)
          .get();
      final userData = userSnapshot.data();

      if (userData != null) {
        final userName = userData['name'] ?? 'Unknown';
        final userEmail = userData['email'] ?? 'Unknown';
        final userId = userData['uid'] ?? 'Unknown';
        print('Participant: Name = $userName, ID = $userId, Email = $userEmail');
      } else {
        print('User data not found for participant ID: $participantId');
      }
    }
  } else {
    print('Chat room data not found.');
  }
}

  @override
  void initState() {
    super.initState();
    // チャットルームの参加者情報をコンソールに表示
    _showParticipants();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('チャット'),
        actions: [
          IconButton(
            icon: Icon(Icons.group_add),
            onPressed: _addParticipants, // 参加者追加ボタン
          ),
        ],
      ),
      body: Column(
        children: [
          // 参加者数表示部分
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chat_rooms')
                .doc(widget.chatRoomId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('エラーが発生しました'));
              }

              final chatRoomData = snapshot.data?.data() as Map<String, dynamic>;
              final participants = chatRoomData?['participants'] ?? [];
              final participantCount = participants.length;

              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  '参加者数: $participantCount人',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(widget.chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('エラーが発生しました'));
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return Center(child: Text('まだメッセージはありません'));
                }

                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data() as Map<String, dynamic>;

                    return _buildMessageCard(data);
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  // メッセージカードを作成
  Widget _buildMessageCard(Map<String, dynamic> data) {
    final senderName = data['senderName'] ?? 'Unknown';
    final text = data['text'] ?? '';
    final timestamp = data['timestamp'] as Timestamp?;
    final time = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Card(
        elevation: 2,
        child: ListTile(
          title: Text(senderName, style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              SizedBox(height: 5),
              if (time != null)
                Text(
                  '${time.hour}:${time.minute} - ${time.year}/${time.month}/${time.day}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'メッセージを入力...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _sendMessage(), // Enterキーで送信
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _sendMessage, // 送信ボタンで送信
          ),
        ],
      ),
    );
  }

  // メッセージ送信
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'text': _messageController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'senderName': user.displayName ?? '匿名',
      });

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'last_message': _messageController.text.trim(),
      });

      _messageController.clear();
    } catch (e) {
      print('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('メッセージ送信に失敗しました。')),
      );
    }
  }
}




class AddParticipantsScreen extends StatefulWidget {
  final String chatRoomId;

  AddParticipantsScreen({required this.chatRoomId});

  @override
  _AddParticipantsScreenState createState() => _AddParticipantsScreenState();
}

class _AddParticipantsScreenState extends State<AddParticipantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  String _searchType = 'name'; // デフォルトで名前で検索

  // 検索タイプを選択
  void _onSearchTypeChanged(String? value) {
    setState(() {
      _searchType = value!;
    });
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final userCollection = FirebaseFirestore.instance.collection('users');
    QuerySnapshot snapshot;

    if (_searchType == 'uid' && query.length == 28) {
      // UIDで検索
      snapshot = await userCollection.where('uid', isEqualTo: query).get();
    } else if (_searchType == 'email') {
      // メールアドレスで検索
      snapshot = await userCollection
          .where('email', isEqualTo: query)
          .get();
    } else {
      // 名前で検索
      snapshot = await userCollection
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: query + '\uf8ff')
          .get();
    }

    setState(() {
      _searchResults = snapshot.docs;
    });
  }

  Future<void> _addParticipant(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(widget.chatRoomId)
          .update({
        'participants': FieldValue.arrayUnion([uid]),
      });

      Navigator.pop(context);
    } catch (e) {
      print('Error adding participant: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('参加者の追加に失敗しました。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('参加者を追加'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 検索タイプを選ぶドロップダウンメニュー
            DropdownButton<String>(
              value: _searchType,
              onChanged: _onSearchTypeChanged,
              items: [
                DropdownMenuItem(
                  value: 'name',
                  child: Text('名前で検索'),
                ),
                DropdownMenuItem(
                  value: 'email',
                  child: Text('メールアドレスで検索'),
                ),
                DropdownMenuItem(
                  value: 'uid',
                  child: Text('UIDで検索'),
                ),
              ],
            ),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '参加者を検索',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: _searchUsers,
                ),
              ),
            ),
            SizedBox(height: 20),
            _searchResults.isNotEmpty
                ? ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      return ListTile(
                        title: Text(user['name']),
                        trailing: IconButton(
                          icon: Icon(Icons.add),
                          onPressed: () => _addParticipant(user['uid']),
                        ),
                      );
                    },
                  )
                : Container(),
          ],
        ),
      ),
    );
  }
}


class LoginScreen extends StatelessWidget {
Future<void> _signInWithGoogle(BuildContext context) async {
  try {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) return; // ユーザーがログインをキャンセル

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);

    final User? user = userCredential.user;

    if (user != null) {
      // ユーザーの名前、ID、メールアドレスをコンソールに表示
      print('User Name: ${user.displayName}');
      print('User ID: ${user.uid}');
      print('User Email: ${user.email}');  // ユーザーのメールアドレスを表示

      // Firestoreにユーザー情報を保存
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await userDoc.set({
        'uid': user.uid,
        'name': user.displayName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // 新規ユーザーのみ追加

      // チャットルーム一覧画面に遷移（Navigator.pushを使用）
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatRoomListScreen()),
      );
    }
  } catch (e) {
    print('Error signing in with Google: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Googleログインに失敗しました。もう一度試してください。')),
    );
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ログイン'),
      ),
      body: Center(
        child: ElevatedButton.icon(
          onPressed: () => _signInWithGoogle(context),
          icon: Icon(Icons.login),
          label: Text('Googleでログイン'),
        ),
      ),
    );
  }
}

class ChatRoomListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('チャットルーム一覧'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              // 新規チャットルーム作成画面へ遷移
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateChatRoomScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chat_rooms').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('エラーが発生しました'));
                }

                final chatRooms = snapshot.data?.docs;

                if (chatRooms == null || chatRooms.isEmpty) {
                  return Center(child: Text('チャットルームはありません'));
                }

                return ListView.builder(
                  itemCount: chatRooms.length,
                  itemBuilder: (context, index) {
                    final chatRoom = chatRooms[index];
                    final roomName = chatRoom['name'] ?? 'No Name';
                    final data = chatRoom.data() as Map<String, dynamic>;
                    final lastMessage = data.containsKey('last_message')
                        ? data['last_message']
                        : 'No messages yet';
                    return ListTile(
                      title: Text(roomName),
                      subtitle: Text('最終メッセージ: $lastMessage'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(chatRoomId: chatRoom.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CreateChatRoomScreen extends StatefulWidget {
  @override
  _CreateChatRoomScreenState createState() => _CreateChatRoomScreenState();
}

class _CreateChatRoomScreenState extends State<CreateChatRoomScreen> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<String> _participants = [];
  List<DocumentSnapshot> _searchResults = [];
  String _searchType = 'name'; // 名前で検索するデフォルト設定

  // 検索タイプを選択するドロップダウンメニュー
  void _onSearchTypeChanged(String? value) {
    setState(() {
      _searchType = value!;
    });
  }

  // 参加者検索
  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final userCollection = FirebaseFirestore.instance.collection('users');
    QuerySnapshot snapshot;

    if (_searchType == 'uid' && query.length == 28) {
      // UIDで検索
      snapshot = await userCollection.where('uid', isEqualTo: query).get();
    } else if (_searchType == 'email') {
      // メールアドレスで検索
      snapshot = await userCollection.where('email', isEqualTo: query).get();
    } else {
      // 名前で検索
      snapshot = await userCollection
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: query + '\uf8ff')
          .get();
    }

    setState(() {
      _searchResults = snapshot.docs;
    });
  }

  // 参加者を追加
  void _addParticipant(String uid) {
    if (!_participants.contains(uid)) {
      setState(() {
        _participants.add(uid);
      });
    }
  }

  // 新しいチャットルームを作成
  Future<void> _createChatRoom() async {
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty || _participants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ルーム名と参加者を追加してください')),
      );
      return;
    }

    try {
      // 新しいチャットルームをFirestoreに追加
      final chatRoomDoc = await FirebaseFirestore.instance.collection('chat_rooms').add({
        'name': roomName,
        'createdAt': FieldValue.serverTimestamp(),
        'participants': _participants, // 参加者リストを保存
        'last_message': '', // 初期状態では空のメッセージ
      });

      // ルーム名と参加者のリセット
      _roomNameController.clear();
      _participants.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('チャットルームが作成されました')),
      );

      // チャットルーム一覧画面に戻る
      Navigator.pop(context);
    } catch (e) {
      print('Error creating chat room: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('チャットルームの作成に失敗しました。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('新規チャットルーム作成'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _roomNameController,
              decoration: InputDecoration(
                labelText: 'チャットルーム名',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            // 検索タイプを選択するドロップダウンメニュー
            DropdownButton<String>(
              value: _searchType,
              onChanged: _onSearchTypeChanged,
              items: [
                DropdownMenuItem(
                  value: 'name',
                  child: Text('名前で検索'),
                ),
                DropdownMenuItem(
                  value: 'email',
                  child: Text('メールアドレスで検索'),
                ),
                DropdownMenuItem(
                  value: 'uid',
                  child: Text('UIDで検索'),
                ),
              ],
            ),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: '参加者を検索',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: _searchUsers,
                ),
              ),
            ),
            SizedBox(height: 20),
            _searchResults.isNotEmpty
                ? ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      return ListTile(
                        title: Text(user['name']),
                        trailing: IconButton(
                          icon: Icon(Icons.add),
                          onPressed: () => _addParticipant(user['uid']),
                        ),
                      );
                    },
                  )
                : Container(),
            SizedBox(height: 20),
            Text('参加者: ${_participants.length}人'),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _participants.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_participants[index]),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: _createChatRoom,
              child: Text('チャットルームを作成'),
            ),
          ],
        ),
      ),
    );
  }
}