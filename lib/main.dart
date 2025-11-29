import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_rag/services/sms_reader_service.dart';
import 'package:sms_rag/services/model_manager.dart';
import 'package:sms_rag/services/rag_service.dart';

void main() {
  runApp(const SmsRagApp());
}

class SmsRagApp extends StatelessWidget {
  const SmsRagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS RAG Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const SmsRagHomePage(),
    );
  }
}

class SmsRagHomePage extends StatefulWidget {
  const SmsRagHomePage({super.key});

  @override
  State<SmsRagHomePage> createState() => _SmsRagHomePageState();
}

class _SmsRagHomePageState extends State<SmsRagHomePage> {
  // Services
  final _smsReader = SmsReaderService();
  final _modelManager = ModelManager();
  final _ragService = RagService();

  // UI State
  bool _isInitialized = false;
  String _statusText = 'Initializing...';
  final TextEditingController _queryController = TextEditingController();
  final List<ChatMessage> _chatMessages = [];
  bool _isSearching = false;

  // SMS Data
  List<SmsMessage> _smsMessages = [];
  int _documentsStored = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Initialize models
      setState(() => _statusText = 'Downloading and loading models...');

      await _modelManager.initializeAll(
        onEmbeddingProgress: (progress, status, isError) {
          if (!isError && progress != null) {
            setState(
              () => _statusText =
                  'Embedding model: ${(progress * 100).toStringAsFixed(0)}%',
            );
          }
        },
        onChatProgress: (progress, status, isError) {
          if (!isError && progress != null) {
            setState(
              () => _statusText =
                  'Chat model: ${(progress * 100).toStringAsFixed(0)}%',
            );
          }
        },
      );

      // Initialize RAG service
      setState(() => _statusText = 'Initializing RAG service...');
      await _ragService.initialize(modelManager: _modelManager);

      setState(() {
        _isInitialized = true;
        _statusText = 'Ready! Load SMS to begin.';
      });
    } catch (e) {
      setState(() => _statusText = 'Initialization failed: $e');
    }
  }

  Future<void> _loadSmsAndIndex() async {
    try {
      setState(() => _statusText = 'Requesting SMS permission...');

      // Request permission
      final hasPermission = await _smsReader.hasPermission();
      if (!hasPermission) {
        final status = await _smsReader.requestPermission();
        if (status != PermissionStatus.granted) {
          setState(() => _statusText = 'SMS permission denied');
          return;
        }
      }

      // Load SMS messages
      setState(() => _statusText = 'Loading SMS messages...');
      _smsMessages = await _smsReader.getAllSms();

      if (_smsMessages.isEmpty) {
        setState(() => _statusText = 'No SMS messages found');
        return;
      }

      // Convert to RAG documents and store
      setState(
        () => _statusText = 'Indexing ${_smsMessages.length} messages...',
      );
      final smsDocuments = _smsMessages
          .map((msg) => msg.toRagDocument())
          .toList();

      await _ragService.storeSmsDocuments(smsDocuments: smsDocuments);

      setState(() {
        _documentsStored = _smsMessages.length;
        _statusText =
            'Indexed ${_smsMessages.length} SMS messages. Ask a question!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Indexed ${_smsMessages.length} SMS messages'),
        ),
      );
    } catch (e) {
      setState(() => _statusText = 'Error loading SMS: $e');
    }
  }

  Future<void> _askQuestion() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || _isSearching) return;

    setState(() {
      _chatMessages.add(ChatMessage(role: 'user', content: query));
      _queryController.clear();
      _isSearching = true;
    });

    try {
      // Search for relevant context
      final context = await _ragService.searchAndGetContext(
        query: query,
        limit: 5,
        maxDistance: 1.2,
      );

      String answer;
      if (context == null || context.isEmpty) {
        answer = 'No relevant SMS messages found for your query.';
      } else {
        // Generate answer using RAG
        answer = await _modelManager.generateRagCompletion(
          query: query,
          context: context,
        );
      }

      setState(() {
        _chatMessages.add(ChatMessage(role: 'assistant', content: answer));
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _chatMessages.add(ChatMessage(role: 'assistant', content: 'Error: $e'));
        _isSearching = false;
      });
    }
  }

  void _clearChat() {
    setState(() => _chatMessages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SMS RAG Demo'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearChat,
              tooltip: 'Clear chat',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.chat), text: 'Chat'),
              Tab(icon: Icon(Icons.message), text: 'SMS'),
              Tab(icon: Icon(Icons.info), text: 'Info'),
            ],
          ),
        ),
        body: !_isInitialized
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_statusText, textAlign: TextAlign.center),
                  ],
                ),
              )
            : TabBarView(
                children: [_buildChatTab(), _buildSmsTab(), _buildInfoTab()],
              ),
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        if (_documentsStored == 0)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.orange.shade100,
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Load SMS messages first to enable Q&A'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _chatMessages.isEmpty
              ? const Center(
                  child: Text('Ask a question about your SMS messages'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatMessages.length + (_isSearching ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_isSearching && i == _chatMessages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final msg = _chatMessages[i];
                    final isUser = msg.role == 'user';

                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 600),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(msg.content),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  enabled: !_isSearching && _documentsStored > 0,
                  decoration: const InputDecoration(
                    hintText: 'Ask about your SMS...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _isSearching ? null : (_) => _askQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSearching || _documentsStored == 0
                    ? null
                    : _askQuestion,
                icon: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Ask'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: _loadSmsAndIndex,
                icon: const Icon(Icons.refresh),
                label: const Text('Load & Index SMS'),
              ),
              const SizedBox(height: 8),
              Text(_statusText, textAlign: TextAlign.center),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _smsMessages.isEmpty
              ? const Center(child: Text('No SMS messages loaded'))
              : ListView.builder(
                  itemCount: _smsMessages.length,
                  itemBuilder: (context, i) {
                    final msg = _smsMessages[i];
                    return ListTile(
                      title: Text(msg.address),
                      subtitle: Text(msg.body),
                      trailing: msg.date != null
                          ? Text(
                              '${msg.date!.day}/${msg.date!.month}',
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard('Models', [
          'Embedding: ${_modelManager.isEmbeddingModelReady ? "✅ Ready" : "❌ Not Ready"}',
          'Chat: ${_modelManager.isChatModelReady ? "✅ Ready" : "❌ Not Ready"}',
        ]),
        _buildInfoCard('Data', [
          'SMS Messages: ${_smsMessages.length}',
          'Documents Indexed: $_documentsStored',
          'RAG Initialized: ${_ragService.isInitialized ? "✅" : "❌"}',
        ]),
        _buildInfoCard('How to Use', [
          '1. Go to SMS tab and load your messages',
          '2. Wait for indexing to complete',
          '3. Go to Chat tab and ask questions',
          '4. Example: "Show me messages from John"',
        ]),
      ],
    );
  }

  Widget _buildInfoCard(String title, List<String> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    _modelManager.dispose();
    _ragService.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String role;
  final String content;

  ChatMessage({required this.role, required this.content});
}
