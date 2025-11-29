import 'package:cactus/services/lm.dart';
import 'package:cactus/models/types.dart';
import 'package:flutter/foundation.dart';

/// Callback for model download progress
typedef DownloadProgressCallback =
    void Function(double? progress, String status, bool isError);

/// Manages initialization and lifecycle of embedding and chat models
class ModelManager {
  final CactusLM _embeddingModel = CactusLM();
  final CactusLM _chatModel = CactusLM();

  bool _embeddingModelReady = false;
  bool _chatModelReady = false;

  /// Check if embedding model is ready
  bool get isEmbeddingModelReady => _embeddingModelReady;

  /// Check if chat model is ready
  bool get isChatModelReady => _chatModelReady;

  /// Check if both models are ready
  bool get isReady => _embeddingModelReady && _chatModelReady;

  /// Initialize embedding model
  ///
  /// [model] - Model name (default: 'qwen3-0.6-embed')
  /// [onProgress] - Optional callback for download progress
  Future<void> initializeEmbeddingModel({
    String model = 'qwen3-0.6-embed',
    DownloadProgressCallback? onProgress,
  }) async {
    try {
      debugPrint('📥 Downloading embedding model: $model');

      // Download the model
      await _embeddingModel.downloadModel(
        model: model,
        downloadProcessCallback: (progress, status, isError) {
          if (onProgress != null) {
            onProgress(progress, status, isError);
          }
          if (!isError && progress != null) {
            debugPrint(
              '📊 Embedding model download: ${(progress * 100).toStringAsFixed(0)}%',
            );
          }
        },
      );

      debugPrint('🔧 Initializing embedding model...');

      // Initialize the model
      await _embeddingModel.initializeModel(
        params: CactusInitParams(model: model),
      );

      _embeddingModelReady = true;
      debugPrint('✅ Embedding model ready: $model');
    } catch (e) {
      debugPrint('❌ Failed to initialize embedding model: $e');
      rethrow;
    }
  }

  /// Initialize chat/completion model
  ///
  /// [model] - Model name (default: 'qwen3-0.6')
  /// [onProgress] - Optional callback for download progress
  Future<void> initializeChatModel({
    String model = 'qwen3-0.6',
    DownloadProgressCallback? onProgress,
  }) async {
    try {
      debugPrint('📥 Downloading chat model: $model');

      // Download the model
      await _chatModel.downloadModel(
        model: model,
        downloadProcessCallback: (progress, status, isError) {
          if (onProgress != null) {
            onProgress(progress, status, isError);
          }
          if (!isError && progress != null) {
            debugPrint(
              '📊 Chat model download: ${(progress * 100).toStringAsFixed(0)}%',
            );
          }
        },
      );

      debugPrint('🔧 Initializing chat model...');

      // Initialize the model
      await _chatModel.initializeModel(params: CactusInitParams(model: model));

      _chatModelReady = true;
      debugPrint('✅ Chat model ready: $model');
    } catch (e) {
      debugPrint('❌ Failed to initialize chat model: $e');
      rethrow;
    }
  }

  /// Initialize both embedding and chat models
  ///
  /// [embeddingModel] - Embedding model name (default: 'qwen3-0.6-embed')
  /// [chatModel] - Chat model name (default: 'qwen3-0.6')
  /// [onEmbeddingProgress] - Optional callback for embedding model download
  /// [onChatProgress] - Optional callback for chat model download
  Future<void> initializeAll({
    String embeddingModel = 'qwen3-0.6-embed',
    String chatModel = 'qwen3-0.6',
    DownloadProgressCallback? onEmbeddingProgress,
    DownloadProgressCallback? onChatProgress,
  }) async {
    await initializeEmbeddingModel(
      model: embeddingModel,
      onProgress: onEmbeddingProgress,
    );

    await initializeChatModel(model: chatModel, onProgress: onChatProgress);
  }

  /// Generate embeddings for given text using the embedding model
  ///
  /// Throws exception if embedding model is not initialized
  Future<List<double>> generateEmbedding(String text) async {
    if (!_embeddingModelReady) {
      throw Exception('Embedding model not initialized');
    }

    debugPrint('🔢 Generating embedding for ${text.length} chars');

    final result = await _embeddingModel.generateEmbedding(text: text);

    if (!result.success || result.embeddings.isEmpty) {
      debugPrint('❌ Embedding generation failed: ${result.errorMessage}');
      throw Exception(result.errorMessage ?? 'Embedding generation failed');
    }

    debugPrint(
      '✅ Embedding generated: dim=${result.dimension}, values=${result.embeddings.length}',
    );

    return result.embeddings;
  }

  /// Generate chat completion using the chat model
  ///
  /// [messages] - List of chat messages
  /// [stripThinkTags] - Whether to remove <think> tags from response (default: true)
  ///
  /// Throws exception if chat model is not initialized
  Future<String> generateCompletion({
    required List<ChatMessage> messages,
    bool stripThinkTags = true,
  }) async {
    if (!_chatModelReady) {
      throw Exception('Chat model not initialized');
    }

    debugPrint('💬 Generating completion for ${messages.length} messages');

    final result = await _chatModel.generateCompletion(messages: messages);

    if (!result.success) {
      debugPrint('❌ Completion failed: ${result.response}');
      throw Exception('Failed to generate completion: ${result.response}');
    }

    debugPrint(
      '✅ Completion generated: ttft=${result.timeToFirstTokenMs.toStringAsFixed(1)}ms, '
      'total=${result.totalTimeMs.toStringAsFixed(1)}ms, '
      'tokens=${result.totalTokens}',
    );

    var response = result.response;

    // Strip thinking tags if requested
    if (stripThinkTags) {
      response = response
          .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>\s*', caseSensitive: false),
            '',
          )
          .trim();
    }

    return response;
  }

  /// Generate chat completion with context for RAG
  ///
  /// [query] - User's question
  /// [context] - Retrieved context from RAG
  /// [systemPrompt] - Optional system prompt (will be prepended to context)
  Future<String> generateRagCompletion({
    required String query,
    required String context,
    String systemPrompt =
        'Answer the question using ONLY the provided CONTEXT. '
        'Do NOT add any information not present in the context. '
        'Do NOT use <think> tags. Be concise and direct.',
  }) async {
    final messages = [
      ChatMessage(
        role: 'system',
        content: '$systemPrompt\n\nCONTEXT:\n$context',
      ),
      ChatMessage(role: 'user', content: query),
    ];

    return await generateCompletion(messages: messages);
  }

  /// Dispose resources
  void dispose() {
    // Add any cleanup if needed
    _embeddingModelReady = false;
    _chatModelReady = false;
  }
}
