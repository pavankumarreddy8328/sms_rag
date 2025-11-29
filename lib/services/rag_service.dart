import 'package:cactus/services/rag.dart';
import 'package:flutter/foundation.dart';
import 'package:sms_rag/services/model_manager.dart';

/// Result from RAG search
class RagSearchResult {
  final String content;
  final double distance;
  final String? fileName;
  final String? filePath;

  RagSearchResult({
    required this.content,
    required this.distance,
    this.fileName,
    this.filePath,
  });

  factory RagSearchResult.fromChunkSearchResult(ChunkSearchResult result) {
    return RagSearchResult(
      content: result.chunk.content,
      distance: result.distance,
      fileName: null, // DocumentChunk doesn't expose fileName
      filePath: null, // DocumentChunk doesn't expose filePath
    );
  }
}

/// Service to manage RAG operations for SMS data
class RagService {
  final CactusRAG _rag = CactusRAG();
  bool _initialized = false;

  /// Check if RAG service is initialized
  bool get isInitialized => _initialized;

  /// Initialize RAG service and connect to model manager
  ///
  /// [modelManager] - ModelManager instance for generating embeddings
  Future<void> initialize({ModelManager? modelManager}) async {
    try {
      debugPrint('🔧 Initializing RAG store...');
      await _rag.initialize();

      if (modelManager != null) {
        // Set embedding generator using the model manager
        _rag.setEmbeddingGenerator((text) async {
          return await modelManager.generateEmbedding(text);
        });

        debugPrint('✅ RAG store initialized with model manager');
      } else {
        debugPrint('✅ RAG store initialized (no model manager)');
      }

      _initialized = true;
    } catch (e) {
      debugPrint('❌ Failed to initialize RAG: $e');
      rethrow;
    }
  }

  /// Store a single document in the RAG store
  ///
  /// [content] - Document content
  /// [fileName] - Optional file name (auto-generated if not provided)
  /// [filePath] - Optional file path
  Future<void> storeDocument({
    required String content,
    String? fileName,
    String? filePath,
  }) async {
    if (!_initialized) {
      throw Exception('RAG service not initialized');
    }

    final name = fileName ?? 'doc_${DateTime.now().millisecondsSinceEpoch}.txt';
    final path = filePath ?? 'memory:$name';

    debugPrint('📝 Storing document: $name (${content.length} chars)');

    await _rag.storeDocument(fileName: name, filePath: path, content: content);

    debugPrint('✅ Document stored: $name');
  }

  /// Store multiple documents in batch
  ///
  /// [documents] - List of document contents
  /// [fileNamePrefix] - Prefix for auto-generated file names
  Future<void> storeDocuments({
    required List<String> documents,
    String fileNamePrefix = 'doc',
  }) async {
    debugPrint('📝 Storing ${documents.length} documents...');

    for (int i = 0; i < documents.length; i++) {
      await storeDocument(
        content: documents[i],
        fileName:
            '${fileNamePrefix}_${i + 1}_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
    }

    debugPrint('✅ All ${documents.length} documents stored');
  }

  /// Store SMS messages as documents
  ///
  /// [smsDocuments] - List of formatted SMS messages
  /// [groupByConversation] - If true, groups messages by sender
  Future<void> storeSmsDocuments({
    required List<String> smsDocuments,
    bool groupByConversation = false,
  }) async {
    await storeDocuments(documents: smsDocuments, fileNamePrefix: 'sms');
  }

  /// Search for relevant documents
  ///
  /// [query] - Search query
  /// [limit] - Maximum number of results (default: 10)
  /// [maxDistance] - Maximum distance threshold for filtering (default: 1.2)
  ///
  /// Returns list of search results sorted by relevance
  Future<List<RagSearchResult>> search({
    required String query,
    int limit = 10,
    double? maxDistance,
  }) async {
    if (!_initialized) {
      throw Exception('RAG service not initialized');
    }

    debugPrint('🔍 Searching: "$query" (limit: $limit)');

    final results = await _rag.search(text: query, limit: limit);

    debugPrint('📊 Found ${results.length} results');

    // Convert to RagSearchResult
    var searchResults = results
        .map((r) => RagSearchResult.fromChunkSearchResult(r))
        .toList();

    // Apply distance threshold if specified
    if (maxDistance != null) {
      final beforeFilter = searchResults.length;
      searchResults = searchResults
          .where((r) => r.distance <= maxDistance)
          .toList();
      debugPrint(
        '🔍 Filtered: $beforeFilter -> ${searchResults.length} (threshold: $maxDistance)',
      );
    }

    return searchResults;
  }

  /// Search and get context string for RAG completion
  ///
  /// [query] - Search query
  /// [limit] - Maximum number of results to include
  /// [maxDistance] - Maximum distance threshold
  /// [separator] - Separator between context chunks (default: '\n---\n')
  ///
  /// Returns formatted context string or null if no relevant results
  Future<String?> searchAndGetContext({
    required String query,
    int limit = 5,
    double maxDistance = 1.2,
    String separator = '\n---\n',
  }) async {
    final results = await search(
      query: query,
      limit: limit,
      maxDistance: maxDistance,
    );

    if (results.isEmpty) {
      debugPrint('⚠️ No relevant context found');
      return null;
    }

    final context = results.map((r) => r.content.trim()).join(separator);

    debugPrint(
      '📄 Context generated: ${context.length} chars from ${results.length} chunks',
    );

    return context;
  }

  /// Get all stored documents
  Future<List<DocumentInfo>> getAllDocuments() async {
    if (!_initialized) {
      throw Exception('RAG service not initialized');
    }

    final docs = await _rag.getAllDocuments();

    return docs.map((doc) {
      final fullContent = doc.chunks.map((c) => c.content).join('');
      return DocumentInfo(
        fileName: doc.fileName,
        filePath: doc.filePath,
        fileSize: doc.fileSize ?? 0,
        chunkCount: doc.chunks.length,
        fullContent: fullContent,
      );
    }).toList();
  }

  /// Clear all documents from the RAG store
  Future<void> clearAllDocuments() async {
    // Note: CactusRAG doesn't have a built-in clear method
    // This would need to be implemented based on the underlying storage
    debugPrint('⚠️ Clear all documents not implemented yet');
  }

  /// Get document count
  Future<int> getDocumentCount() async {
    final docs = await getAllDocuments();
    return docs.length;
  }

  /// Dispose resources
  void dispose() {
    _initialized = false;
  }
}

/// Information about a stored document
class DocumentInfo {
  final String fileName;
  final String filePath;
  final int fileSize;
  final int chunkCount;
  final String fullContent;

  DocumentInfo({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.chunkCount,
    required this.fullContent,
  });

  String get contentPreview {
    return fullContent.length > 400
        ? '${fullContent.substring(0, 400)}...'
        : fullContent;
  }
}
