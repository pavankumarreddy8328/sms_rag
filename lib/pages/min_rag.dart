import 'package:flutter/material.dart';
import 'package:cactus/services/lm.dart';
import 'package:cactus/services/rag.dart';

class MinRAGPage extends StatefulWidget {
  const MinRAGPage({super.key});
  @override
  State<MinRAGPage> createState() => _MinRAGPageState();
}

class _MinRAGPageState extends State<MinRAGPage> {
  final lm = CactusLM();
  final rag = CactusRAG();
  final TextEditingController query = TextEditingController();
  final TextEditingController doc = TextEditingController();
  List<ChunkSearchResult> results = [];
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await rag.initialize();
    await lm.initializeModel();
    rag.setEmbeddingGenerator((text) async {
      final res = await lm.generateEmbedding(text: text);
      if (!res.success || res.embeddings.isEmpty) {
        throw Exception(res.errorMessage ?? 'Embedding failed');
      }
      return res.embeddings;
    });
    setState(() => ready = true);
  }

  Future<void> _storeDoc() async {
    final content = doc.text.trim();
    if (content.isEmpty) return;
    final name = 'inline_${DateTime.now().millisecondsSinceEpoch}.txt';
    await rag.storeDocument(fileName: name, filePath: 'memory:inline', content: content);
    doc.clear();
  }

  Future<void> _run() async {
    final q = query.text.trim();
    if (q.isEmpty) return;
    final r = await rag.search(text: q, limit: 5);
    setState(() => results = r);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: doc,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Inline document', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(onPressed: _storeDoc, child: const Text('Store')),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: query,
                decoration: const InputDecoration(hintText: 'Ask…', border: OutlineInputBorder()),
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _run, child: const Text('Search')),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final r = results[i];
                return ListTile(
                  title: Text(r.chunk.content),
                  subtitle: Text('distance: ${r.distance.toStringAsFixed(4)}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
