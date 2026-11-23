import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// アプリ起動最初の関数
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '江東区 ゴミ分別AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const GarbageSortPage(),
    );
  }
}

class GarbageSortPage extends StatefulWidget {
  const GarbageSortPage({super.key});

  @override
  State<GarbageSortPage> createState() => _GarbageSortPageState();
}

class _GarbageSortPageState extends State<GarbageSortPage> {
  static const String apiUrl = 'http://192.168.3.12:8000/classify';

  File? _image; // カメラで撮った画像
  bool _isLoading = false; // AIが判定中かどうか
  Map<String, dynamic>? _result; // FastAPIから返ってきたJSONデータ
  String? _error; // 通信失敗時などのエラーメッセージ

  // 現在メイン表示している品目情報（代替候補をタップしたときに切り替え用）
  String? _selectedItem; // 品目
  String? _selectedCategory; // 分別区分
  String? _selectedMemo; // 備考

  // 特定の画像をFastAPIに送る処理
  Future<void> _pickAndClassify(ImageSource source) async {
    final picker = ImagePicker();
    // 写真をそのまま送ると遅くなるため縦横最大1024px、画質80%で取り込む
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    // カメラやアルバムなど何もせずキャンセルを押した場合、通信処理をせずそのまま終了させる
    if (picked == null) return;

    // 画面を読み込み中にする
    setState(() {
      _image = File(picked.path); // 撮った画像をプレビュー用にセット
      _isLoading = true; // 読み込み中にする
      // 初期化する(前回の判定結果やエラーなどのリセット)
      _result = null;
      _error = null;
      _selectedItem = null;
      _selectedCategory = null;
      _selectedMemo = null;
    });

    try {
      // FastAPIへ画像を送信
      final request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.files.add(await http.MultipartFile.fromPath('file', picked.path));

      // サーバーへ送信後待機(最大20秒過ぎたらタイムアウト)
      final streamedRes = await request.send().timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamedRes);

      // 通信成功した場合、返ってきたJSONを日本語対応で読み込む処理
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _result = data;
          _selectedItem = data['item'];
          _selectedCategory = data['category'];
          _selectedMemo = data['memo'];
        });
      } else { // サーバー側でエラーが発生した場合
        setState(() => _error = 'サーバーエラー: ${response.statusCode}');
      }
    } catch (e) { // 通信自体の失敗を受け止め、アプリが落ちないようにする
      setState(() => _error = '通信エラー: サーバーが起動しているか、同じWi-Fiか確認してください\n($e)');
    } finally {
      setState(() => _isLoading = false); // 通信エラーでも必ず通信モーションを止める
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('江東区 ゴミ分別AI'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 撮影・写真選択ボタン
            Row(
              children: [
                // 撮影ボタン
                Expanded(
                  child: FilledButton.icon(
                    // 通信中に押されるのを防ぎ、ボタン連打を防ぐ
                    onPressed: _isLoading ? null : () => _pickAndClassify(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('カメラで撮る'),
                  ),
                ),
                const SizedBox(width: 12),
                // 写真選択ボタン
                Expanded(
                  child: OutlinedButton.icon(
                    // 通信中に押されるのを防ぎ、ボタン連打を防ぐ
                    onPressed: _isLoading ? null : () => _pickAndClassify(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('写真を選ぶ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 選んだ画像のプレビュー
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!, height: 240, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),

            // ローディング 
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('AIが分別を判定中...'),
                  ],
                ),
              ), 
            // エラー内容を表示
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
              ),
            // 結果を表示
            if (_result != null) _buildResultCard(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> res) {
    // alternativesの型をListとして扱う
    final alternatives = (res['alternatives'] as List<dynamic>?) ?? [];
    // nullが返ってきても空文字を使う
    final status = res['status'] ?? '';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 判定ステータスバッジ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: TextStyle(color: Colors.teal.shade800, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),

            // 分別区分・品目名
            Text(
              _selectedCategory ?? '',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            const SizedBox(height: 4),
            Text(
              '品目：${_selectedItem ?? ''}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const Divider(height: 24),

            // 素材・注意点・備考
            Text('検出素材：${res['material']}'),
            if (res['brand'] != null && res['brand'] != '-')
              Text('ブランド：${res['brand']}'),
            const SizedBox(height: 6),
            Text(
              '注意点：${res['alert']}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
            // 備考がある場合だけ表示
            if (_selectedMemo != null && _selectedMemo != '-') ...[
              const SizedBox(height: 8),
              Text('江東区 備考：$_selectedMemo', style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],

            // 代替候補（タップでメイン表示を切り替え）
            if (alternatives.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('違う場合はこちらかも？（タップで切替）', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...alternatives.map((alt) {
                return Card(
                  color: Colors.grey.shade50,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text('${alt['item']}（${alt['category']}）'),
                    subtitle: Text(alt['memo'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    // 候補をタップで、結果カードを書き換え
                    onTap: () {
                      setState(() {
                        _selectedItem = alt['item'];
                        _selectedCategory = alt['category'];
                        _selectedMemo = alt['memo'];
                      });
                    },
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
