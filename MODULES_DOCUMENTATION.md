# SMS RAG Modular Architecture

This document describes the modular architecture of the SMS RAG application, designed to separate concerns and make it easy to build a Retrieval-Augmented Generation (RAG) system on top of SMS data.

## Architecture Overview

The application is structured into three main service modules:

```
lib/
├── main.dart                           # Main app UI and orchestration
├── services/
│   ├── sms_reader_service.dart        # SMS reading and permission handling
│   ├── model_manager.dart             # AI model initialization and inference
│   └── rag_service.dart               # Document storage and retrieval
└── pages/
    └── min_rag.dart                   # Minimal RAG example (reference)
```

## Module Details

### 1. SMS Reader Service (`sms_reader_service.dart`)

**Purpose**: Handles all SMS-related operations including permission management and data retrieval.

**Key Classes**:
- `SmsMessage`: Model representing an SMS message with fields for address, body, date, and type
- `SmsReaderService`: Service class for reading SMS from Android device

**Key Methods**:
```dart
// Permission management
Future<PermissionStatus> requestPermission()
Future<bool> hasPermission()

// SMS retrieval
Future<List<SmsMessage>> getAllSms()
Future<List<String>> getSmsAsDocuments()  // RAG-ready format

// Filtering and search
Future<Map<String, List<SmsMessage>>> getSmsGroupedBySender()
Future<List<SmsMessage>> getConversationWith(String address)
Future<List<SmsMessage>> getSmsInDateRange(DateTime start, DateTime end)
Future<List<SmsMessage>> searchSms(String query)
```

**Usage Example**:
```dart
final smsReader = SmsReaderService();

// Request permission
await smsReader.requestPermission();

// Load all SMS
final messages = await smsReader.getAllSms();

// Get SMS as RAG documents
final documents = await smsReader.getSmsAsDocuments();

// Search specific messages
final filtered = await smsReader.searchSms("meeting");
```

**Document Format**:
Each SMS is formatted as:
```
From: [phone_number]
Date: [timestamp]
Message: [body_text]
```

---

### 2. Model Manager (`model_manager.dart`)

**Purpose**: Manages the lifecycle of AI models (embedding and chat) used for RAG operations.

**Key Classes**:
- `ModelManager`: Handles initialization and inference for both embedding and chat models

**Key Methods**:
```dart
// Initialization
Future<void> initializeEmbeddingModel({
  String model = 'qwen3-0.6-embed',
  DownloadProgressCallback? onProgress,
})

Future<void> initializeChatModel({
  String model = 'qwen3-0.6',
  DownloadProgressCallback? onProgress,
})

Future<void> initializeAll()  // Initialize both models

// Inference
Future<List<double>> generateEmbedding(String text)
Future<String> generateCompletion({
  required List<ChatMessage> messages,
  bool stripThinkTags = true,
})

// RAG-specific
Future<String> generateRagCompletion({
  required String query,
  required String context,
  String systemPrompt = '...',
})

// Status
bool get isReady
bool get isEmbeddingModelReady
bool get isChatModelReady
```

**Usage Example**:
```dart
final modelManager = ModelManager();

// Initialize both models with progress tracking
await modelManager.initializeAll(
  onEmbeddingProgress: (progress, status, isError) {
    print('Embedding: ${(progress * 100).toStringAsFixed(0)}%');
  },
  onChatProgress: (progress, status, isError) {
    print('Chat: ${(progress * 100).toStringAsFixed(0)}%');
  },
);

// Generate embedding for text
final embedding = await modelManager.generateEmbedding("Hello world");

// Generate RAG completion
final answer = await modelManager.generateRagCompletion(
  query: "What did John say?",
  context: "John said hello yesterday.",
);
```

---

### 3. RAG Service (`rag_service.dart`)

**Purpose**: Manages document storage, embedding generation, and semantic search for retrieval operations.

**Key Classes**:
- `RagService`: Main service for RAG operations
- `RagSearchResult`: Represents a search result with content and relevance score
- `DocumentInfo`: Information about stored documents

**Key Methods**:
```dart
// Initialization
Future<void> initialize({ModelManager? modelManager})

// Document storage
Future<void> storeDocument({
  required String content,
  String? fileName,
  String? filePath,
})

Future<void> storeDocuments({
  required List<String> documents,
  String fileNamePrefix = 'doc',
})

Future<void> storeSmsDocuments({
  required List<String> smsDocuments,
  bool groupByConversation = false,
})

// Search and retrieval
Future<List<RagSearchResult>> search({
  required String query,
  int limit = 10,
  double? maxDistance,
})

Future<String?> searchAndGetContext({
  required String query,
  int limit = 5,
  double maxDistance = 1.2,
  String separator = '\n---\n',
})

// Management
Future<List<DocumentInfo>> getAllDocuments()
Future<int> getDocumentCount()
```

**Usage Example**:
```dart
final ragService = RagService();

// Initialize with model manager
await ragService.initialize(modelManager: modelManager);

// Store SMS documents
await ragService.storeSmsDocuments(
  smsDocuments: smsDocuments,
);

// Search for relevant content
final results = await ragService.search(
  query: "messages about meeting",
  limit: 5,
  maxDistance: 1.2,
);

// Get context for RAG
final context = await ragService.searchAndGetContext(
  query: "What did Jane say about the project?",
);
```

**Distance Threshold**:
- Uses L2 normalized embeddings (Euclidean distance 0-2)
- 0 = identical vectors
- ~1.0 = roughly orthogonal
- < 1.2 = reasonably similar (recommended threshold)
- 2 = opposite vectors

---

## Integration Example

Here's how all three modules work together in a complete RAG pipeline:

```dart
class SmsRagApp extends StatefulWidget {
  @override
  State<SmsRagApp> createState() => _SmsRagAppState();
}

class _SmsRagAppState extends State<SmsRagApp> {
  final smsReader = SmsReaderService();
  final modelManager = ModelManager();
  final ragService = RagService();

  @override
  void initState() {
    super.initState();
    _setupRagPipeline();
  }

  Future<void> _setupRagPipeline() async {
    // Step 1: Initialize models
    await modelManager.initializeAll();

    // Step 2: Initialize RAG with model manager
    await ragService.initialize(modelManager: modelManager);

    // Step 3: Load and index SMS
    final hasPermission = await smsReader.hasPermission();
    if (!hasPermission) {
      await smsReader.requestPermission();
    }

    final smsDocuments = await smsReader.getSmsAsDocuments();
    await ragService.storeSmsDocuments(smsDocuments: smsDocuments);

    print('✅ RAG pipeline ready!');
  }

  Future<String> askQuestion(String query) async {
    // Step 1: Retrieve relevant context
    final context = await ragService.searchAndGetContext(
      query: query,
      limit: 5,
      maxDistance: 1.2,
    );

    if (context == null) {
      return "No relevant messages found.";
    }

    // Step 2: Generate answer using LLM
    return await modelManager.generateRagCompletion(
      query: query,
      context: context,
    );
  }
}
```

## Advanced Use Cases

### 1. Time-Based SMS Analysis
```dart
// Get recent messages
final lastWeek = DateTime.now().subtract(Duration(days: 7));
final recentSms = await smsReader.getSmsInDateRange(
  lastWeek,
  DateTime.now(),
);

// Store as separate documents
await ragService.storeDocuments(
  documents: recentSms.map((msg) => msg.toRagDocument()).toList(),
  fileNamePrefix: 'recent_sms',
);
```

### 2. Conversation-Specific RAG
```dart
// Get conversation with specific contact
final conversation = await smsReader.getConversationWith("+1234567890");

// Store conversation
await ragService.storeDocuments(
  documents: conversation.map((msg) => msg.toRagDocument()).toList(),
  fileNamePrefix: 'conversation',
);

// Ask questions about this conversation
final context = await ragService.searchAndGetContext(
  query: "What did we discuss about the project?",
);
```

### 3. Grouped Analysis
```dart
// Group by sender
final grouped = await smsReader.getSmsGroupedBySender();

// Store each conversation separately
for (var entry in grouped.entries) {
  final sender = entry.key;
  final messages = entry.value;
  
  await ragService.storeDocuments(
    documents: messages.map((msg) => msg.toRagDocument()).toList(),
    fileNamePrefix: 'sender_${sender.hashCode}',
  );
}
```

### 4. Custom System Prompts
```dart
// Financial query with custom prompt
final answer = await modelManager.generateRagCompletion(
  query: "How much did I spend on groceries?",
  context: relevantMessages,
  systemPrompt: '''
You are a financial assistant analyzing SMS messages.
Extract monetary amounts and categorize expenses.
Only use information from the provided messages.
''',
);
```

## Benefits of This Architecture

1. **Separation of Concerns**: Each module has a single, well-defined responsibility
2. **Testability**: Modules can be tested independently
3. **Reusability**: Services can be used in different parts of the app or other projects
4. **Maintainability**: Changes to one module don't affect others
5. **Extensibility**: Easy to add new features (e.g., email reader, file system reader)
6. **Type Safety**: Strong typing with models like `SmsMessage` and `RagSearchResult`

## Performance Considerations

1. **Batch Processing**: Use `storeSmsDocuments()` for bulk operations
2. **Distance Threshold**: Adjust `maxDistance` parameter to balance precision/recall
3. **Result Limits**: Use appropriate `limit` values to avoid processing too many results
4. **Caching**: Consider caching frequently accessed conversations
5. **Lazy Loading**: Load SMS on-demand rather than all at once for large datasets

## Next Steps

To extend this architecture:

1. Add more data sources (emails, notes, files)
2. Implement conversation threading
3. Add metadata filtering (date ranges, senders)
4. Create specialized prompts for different query types
5. Implement conversation memory for multi-turn chat
6. Add export functionality for retrieved data

## Platform Requirements

- **Android Only**: SMS reading requires Android platform
- **Permissions**: `READ_SMS` permission required
- **Models**: Cactus package with qwen3 models
- **Flutter**: Compatible with Flutter 3.0+
