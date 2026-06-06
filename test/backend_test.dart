import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent/backend_utils.dart';

void main() {
  // ==================== isDashScopeUrl 测试 ====================
  group('isDashScopeUrl()', () {
    test('包含 dashscope 的 URL 返回 true', () {
      expect(
        isDashScopeUrl('https://dashscope.aliyuncs.com/compatible-mode/v1'),
        isTrue,
      );
    });

    test('包含 aliyuncs.com 的 URL 返回 true', () {
      expect(
        isDashScopeUrl('https://dashscope-intl.aliyuncs.com/v1'),
        isTrue,
      );
    });

    test('不相关的 URL 返回 false', () {
      expect(
        isDashScopeUrl('https://api.deepseek.com/v1'),
        isFalse,
      );
    });

    test('空字符串返回 false', () {
      expect(isDashScopeUrl(''), isFalse);
    });

    test('大小写不敏感', () {
      expect(
        isDashScopeUrl('https://DASHSCOPE.aliyuncs.com/v1'),
        isTrue,
      );
    });
  });

  // ==================== getWebSearchConfig 测试 ====================
  group('getWebSearchConfig()', () {
    test('正常读取配置', () {
      final config = {
        'WEB_SEARCH_CONFIG': {
          'enabled': true,
          'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          'api_key': 'sk-test',
          'model': 'qwen3.5-flash',
        },
      };

      final wsc = getWebSearchConfig(config);

      expect(wsc.enabled, isTrue);
      expect(wsc.baseUrl, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
      expect(wsc.apiKey, 'sk-test');
      expect(wsc.model, 'qwen3.5-flash');
    });

    test('空 map 返回默认配置', () {
      final wsc = getWebSearchConfig({});

      expect(wsc.enabled, isFalse);
      expect(wsc.baseUrl, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
      expect(wsc.apiKey, '');
      expect(wsc.model, 'qwen3.5-flash');
    });

    test('部分配置时默认值正确合并', () {
      final config = {
        'WEB_SEARCH_CONFIG': {
          'enabled': true,
          'api_key': 'sk-partial',
        },
      };

      final wsc = getWebSearchConfig(config);

      expect(wsc.enabled, isTrue);
      expect(wsc.apiKey, 'sk-partial');
      // 未提供的字段使用默认值
      expect(wsc.baseUrl, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
      expect(wsc.model, 'qwen3.5-flash');
    });

    test('WEB_SEARCH_CONFIG 不是 map 时返回默认值', () {
      final config = {'WEB_SEARCH_CONFIG': 'invalid'};

      final wsc = getWebSearchConfig(config);

      expect(wsc.enabled, isFalse);
      expect(wsc.apiKey, '');
    });
  });

  // ==================== setWebSearchConfig 测试 ====================
  group('setWebSearchConfig()', () {
    test('写入并读取往返', () {
      final config = <String, dynamic>{};
      final wsc = WebSearchConfig(
        enabled: true,
        baseUrl: 'https://test.api.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );

      setWebSearchConfig(config, wsc);
      final restored = getWebSearchConfig(config);

      expect(restored.enabled, wsc.enabled);
      expect(restored.baseUrl, wsc.baseUrl);
      expect(restored.apiKey, wsc.apiKey);
      expect(restored.model, wsc.model);
    });

    test('覆盖已有配置', () {
      final config = <String, dynamic>{
        'WEB_SEARCH_CONFIG': {
          'enabled': false,
          'base_url': 'https://old.com',
          'api_key': 'sk-old',
          'model': 'old-model',
        },
      };

      final newWsc = WebSearchConfig(
        enabled: true,
        baseUrl: 'https://new.com',
        apiKey: 'sk-new',
        model: 'new-model',
      );

      setWebSearchConfig(config, newWsc);
      final restored = getWebSearchConfig(config);

      expect(restored.enabled, isTrue);
      expect(restored.baseUrl, 'https://new.com');
      expect(restored.apiKey, 'sk-new');
      expect(restored.model, 'new-model');
    });
  });

  // ==================== getAiConfigs / setAiConfigs 补充测试 ====================
  group('AI 配置管理函数补充', () {
    test('setAiConfigs 空列表写入', () {
      final config = <String, dynamic>{};
      setAiConfigs(config, []);

      expect(config.containsKey('AI_CONFIGS'), isTrue);
      expect(config['AI_CONFIGS'], []);
    });

    test('getAiConfigs AI_CONFIGS 为 null 时返回空', () {
      final config = {'AI_CONFIGS': null};
      expect(getAiConfigs(config), []);
    });

    test('getEnabledAiConfig 多个启用时返回第一个', () {
      final config = {
        'AI_CONFIGS': [
          {'name': 'AI1', 'base_url': '', 'api_key': '', 'model': '', 'enabled': true},
          {'name': 'AI2', 'base_url': '', 'api_key': '', 'model': '', 'enabled': true},
        ],
      };

      final enabled = getEnabledAiConfig(config);
      expect(enabled, isNotNull);
      expect(enabled!.name, 'AI1');
    });
  });
}
