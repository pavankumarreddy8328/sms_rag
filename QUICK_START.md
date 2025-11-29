# SMS RAG - Quick Start Guide

## Project Structure

```
lib/
├── main.dart                      # Main app with UI
└── services/
    ├── sms_reader_service.dart   # SMS reading & permissions
    ├── model_manager.dart         # AI models (embedding + chat)
    └── rag_service.dart          # Document storage & search
```

## Module Responsibilities

### 📱 SMS Reader Service
- Handles SMS permissions
- Reads messages from Android
- Formats messages for RAG
- Provides filtering utilities

### 🤖 Model Manager
- Downloads and initializes AI models
- Generates embeddings for text
- Generates chat completions
- Provides RAG-specific completion methods

### 🔍 RAG Service
- Stores documents with embeddings
- Performs semantic search
- Retrieves relevant context
- Manages document lifecycle

## Basic Usage

### 1. Initialize Everything
```dart
// Create service instances
final smsReader = SmsReaderService();
final modelManager = ModelManager();
final ragService = RagService();

// Initialize models (this takes time!)
await modelManager.initializeAll();

// Initialize RAG with model manager
await ragService.initialize(modelManager: modelManager);
```

### 2. Load and Index SMS
```dart
// Request permission if needed
if (!await smsReader.hasPermission()) {
  await smsReader.requestPermission();
}

// Load SMS messages
final messages = await smsReader.getAllSms();
print('Loaded ${messages.length} messages');

// Convert to RAG documents and store
final documents = await smsReader.getSmsAsDocuments();
await ragService.storeSmsDocuments(smsDocuments: documents);
print('Indexed ${documents.length} messages');
```

### 3. Ask Questions
```dart
// Search for relevant context
final context = await ragService.searchAndGetContext(
  query: "What did John say about the meeting?",
  limit: 5,
  maxDistance: 1.2,
);

if (context != null) {
  // Generate answer using RAG
  final answer = await modelManager.generateRagCompletion(
    query: "What did John say about the meeting?",
    context: context,
  );
  print(answer);
} else {
  print('No relevant messages found');
}
```

## Common Patterns

### Pattern 1: Full RAG Pipeline
```dart
Future<String> askSmsQuestion(String question) async {
  // 1. Retrieve relevant SMS
  final context = await ragService.searchAndGetContext(
    query: question,
    limit: 5,
    maxDistance: 1.2,
  );

  // 2. Generate answer
  if (context == null) return "No relevant messages found.";
  
  return await modelManager.generateRagCompletion(
    query: question,
    context: context,
  );
}
```

### Pattern 2: Filter Then Index
```dart
// Get messages from last week
final lastWeek = DateTime.now().subtract(Duration(days: 7));
final recent = await smsReader.getSmsInDateRange(lastWeek, DateTime.now());

// Index only recent messages
final docs = recent.map((msg) => msg.toRagDocument()).toList();
await ragService.storeDocuments(documents: docs, fileNamePrefix: 'recent');
```

### Pattern 3: Conversation-Specific Search
```dart
// Get conversation with specific person
final conversation = await smsReader.getConversationWith("+1234567890");

// Index this conversation separately
final docs = conversation.map((msg) => msg.toRagDocument()).toList();
await ragService.storeDocuments(documents: docs, fileNamePrefix: 'john');

// Now search only returns results from this conversation
```

## Key Methods Reference

### SmsReaderService
```dart
hasPermission()                    // Check if permission granted
requestPermission()                // Request SMS permission
getAllSms()                        // Get all SMS messages
getSmsAsDocuments()                // Get SMS formatted for RAG
searchSms(query)                   // Search SMS by content
getConversationWith(address)       // Get messages from one sender
getSmsInDateRange(start, end)      // Get messages in date range
```

### ModelManager
```dart
initializeAll()                    // Init both models
generateEmbedding(text)            // Get embedding vector
generateRagCompletion(query, context)  // Answer with RAG
isReady                            // Check if ready
```

### RagService
```dart
initialize(modelManager)           // Setup RAG with models
storeDocument(content)             // Store one document
storeSmsDocuments(smsDocuments)    // Store SMS messages
search(query, limit, maxDistance)  // Search for matches
searchAndGetContext(query)         // Get formatted context
getAllDocuments()                  // List stored documents
```

## Tips & Best Practices

### Performance
- **Batch operations**: Use `storeSmsDocuments()` instead of multiple `storeDocument()` calls
- **Limit results**: Don't retrieve more than you need (default limit: 5-10)
- **Adjust threshold**: Lower `maxDistance` for more precise results (0.8-1.0), higher for recall (1.2-1.5)

### Accuracy
- **Context quality**: More relevant context = better answers
- **Query specificity**: Specific questions get better results
- **Distance threshold**: 1.2 is a good starting point for normalized embeddings

### Memory
- **Lazy loading**: Don't load all SMS at once if you have thousands
- **Filter first**: Use date ranges or sender filters before indexing
- **Clear unused**: Dispose services when done

## Example Queries

Good queries for SMS RAG:
- "What did Sarah say about the project deadline?"
- "Show messages mentioning the address"
- "When did I last hear from the bank?"
- "What plans were made for this weekend?"
- "Find messages about payment or invoice"

## Troubleshooting

### Models not downloading
- Check internet connection
- Verify disk space available
- Check logs for download progress

### No search results
- Verify documents are stored: `ragService.getDocumentCount()`
- Try higher `maxDistance` (e.g., 1.5)
- Check if query matches SMS content
- Ensure models are initialized

### Permission denied
- Check Android permissions in settings
- Request permission at runtime
- Handle permanently denied case

### Out of memory
- Reduce batch size when storing documents
- Lower search result limit
- Don't store all SMS if you have thousands

## Next Steps

1. ✅ Load your SMS messages
2. ✅ Index them with RAG
3. ✅ Ask questions
4. 🚀 Build custom features on top!

Ideas for extensions:
- Add filters by sender, date, or content type
- Create conversation summaries
- Build SMS analytics dashboard
- Export search results
- Add voice input for queries
- Implement conversation memory for follow-up questions
