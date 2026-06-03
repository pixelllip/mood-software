import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/services/local_backend.dart';

void main() {
  // ==================== AiConfig 测试 ====================
  group('AiConfig', () {
    test('toJson 序列化', () {
      final config = AiConfig(
        name: '测试AI',
        baseUrl: 'https://api.test.com/v1',
        apiKey: 'sk-test-key',
        model: 'gpt-4',
        enabled: true,
      );

      final json = config.toJson();

      expect(json['name'], '测试AI');
      expect(json['base_url'], 'https://api.test.com/v1');
      expect(json['api_key'], 'sk-test-key');
      expect(json['model'], 'gpt-4');
      expect(json['enabled'], true);
    });

    test('fromJson 反序列化', () {
      final json = {
        'name': '测试AI',
        'base_url': 'https://api.test.com/v1',
        'api_key': 'sk-test-key',
        'model': 'gpt-4',
        'enabled': true,
      };

      final config = AiConfig.fromJson(json);

      expect(config.name, '测试AI');
      expect(config.baseUrl, 'https://api.test.com/v1');
      expect(config.apiKey, 'sk-test-key');
      expect(config.model, 'gpt-4');
      expect(config.enabled, true);
    });

    test('fromJson 处理缺失字段', () {
      final config = AiConfig.fromJson({});

      expect(config.name, '');
      expect(config.baseUrl, '');
      expect(config.apiKey, '');
      expect(config.model, '');
      expect(config.enabled, false);
    });

    test('toJson / fromJson 往返', () {
      final original = AiConfig(
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-ds-key',
        model: 'deepseek-chat',
        enabled: true,
      );

      final json = original.toJson();
      final restored = AiConfig.fromJson(json);

      expect(restored.name, original.name);
      expect(restored.baseUrl, original.baseUrl);
      expect(restored.apiKey, original.apiKey);
      expect(restored.model, original.model);
      expect(restored.enabled, original.enabled);
    });

    test('copyWith 部分更新', () {
      final original = AiConfig(
        name: '测试AI',
        baseUrl: 'https://api.test.com',
        apiKey: 'old-key',
        model: 'gpt-3.5',
        enabled: false,
      );

      final updated = original.copyWith(
        model: 'gpt-4',
        enabled: true,
      );

      expect(updated.name, '测试AI'); // 不变
      expect(updated.baseUrl, 'https://api.test.com'); // 不变
      expect(updated.apiKey, 'old-key'); // 不变
      expect(updated.model, 'gpt-4'); // 更新
      expect(updated.enabled, true); // 更新
    });

    test('copyWith 全量更新', () {
      final original = AiConfig(
        name: '旧AI',
        baseUrl: 'https://old.com',
        apiKey: 'old-key',
        model: 'old-model',
        enabled: false,
      );

      final updated = original.copyWith(
        name: '新AI',
        baseUrl: 'https://new.com',
        apiKey: 'new-key',
        model: 'new-model',
        enabled: true,
      );

      expect(updated.name, '新AI');
      expect(updated.baseUrl, 'https://new.com');
      expect(updated.apiKey, 'new-key');
      expect(updated.model, 'new-model');
      expect(updated.enabled, true);
    });
  });

  // ==================== getAiConfigs / getEnabledAiConfig / setAiConfigs ====================
  group('AI 配置管理函数', () {
    test('getAiConfigs 读取配置列表', () {
      final config = {
        'AI_CONFIGS': [
          {'name': 'AI1', 'base_url': '', 'api_key': '', 'model': '', 'enabled': false},
          {'name': 'AI2', 'base_url': '', 'api_key': '', 'model': '', 'enabled': true},
        ],
      };

      final configs = getAiConfigs(config);

      expect(configs.length, 2);
      expect(configs[0].name, 'AI1');
      expect(configs[1].name, 'AI2');
      expect(configs[1].enabled, true);
    });

    test('getAiConfigs 处理空列表', () {
      final configs = getAiConfigs({});
      expect(configs, []);
    });

    test('getAiConfigs 处理 null AI_CONFIGS', () {
      final config = {'AI_CONFIGS': null};
      final configs = getAiConfigs(config);
      expect(configs, []);
    });

    test('getEnabledAiConfig 返回第一个启用的配置', () {
      final config = {
        'AI_CONFIGS': [
          {'name': 'AI1', 'base_url': '', 'api_key': '', 'model': '', 'enabled': false},
          {'name': 'AI2', 'base_url': '', 'api_key': '', 'model': '', 'enabled': true},
          {'name': 'AI3', 'base_url': '', 'api_key': '', 'model': '', 'enabled': true},
        ],
      };

      final enabled = getEnabledAiConfig(config);
      expect(enabled, isNotNull);
      expect(enabled!.name, 'AI2');
    });

    test('getEnabledAiConfig 无启用配置时返回 null', () {
      final config = {
        'AI_CONFIGS': [
          {'name': 'AI1', 'base_url': '', 'api_key': '', 'model': '', 'enabled': false},
        ],
      };

      expect(getEnabledAiConfig(config), isNull);
    });

    test('getEnabledAiConfig 空列表返回 null', () {
      expect(getEnabledAiConfig({}), isNull);
    });

    test('setAiConfigs 写入并读取往返', () {
      final configs = [
        AiConfig(name: 'AI1', baseUrl: 'url1', apiKey: 'key1', model: 'm1', enabled: false),
        AiConfig(name: 'AI2', baseUrl: 'url2', apiKey: 'key2', model: 'm2', enabled: true),
      ];

      final config = <String, dynamic>{};
      setAiConfigs(config, configs);

      expect(config.containsKey('AI_CONFIGS'), isTrue);
      final read = getAiConfigs(config);
      expect(read.length, 2);
      expect(read[0].name, 'AI1');
      expect(read[1].name, 'AI2');
      expect(read[1].enabled, true);
    });
  });

  // ==================== BacklogMessage 测试 ====================
  group('BacklogMessage', () {
    test('toJson 序列化', () {
      final msg = BacklogMessage(role: 'user', content: '你好');
      final json = msg.toJson();
      expect(json['role'], 'user');
      expect(json['content'], '你好');
    });

    test('fromJson 反序列化', () {
      final json = {'role': 'assistant', 'content': '你好！有什么可以帮助你的吗？'};
      final msg = BacklogMessage.fromJson(json);
      expect(msg.role, 'assistant');
      expect(msg.content, '你好！有什么可以帮助你的吗？');
    });

    test('fromJson 处理空字段', () {
      final msg = BacklogMessage.fromJson({});
      expect(msg.role, '');
      expect(msg.content, '');
    });

    test('toJson / fromJson 往返', () {
      final original = BacklogMessage(
        role: 'system',
        content: '你是一个智能学习助手',
      );
      final json = original.toJson();
      final restored = BacklogMessage.fromJson(json);
      expect(restored.role, original.role);
      expect(restored.content, original.content);
    });
  });

  // ==================== StudentData 测试 ====================
  group('StudentData', () {
    test('toJson 序列化', () {
      final student = StudentData(
        studentId: '2024001',
        name: '张三',
        scores: {'数学': 95, '英语': 88},
      );

      final json = student.toJson();

      expect(json['student_id'], '2024001');
      expect(json['name'], '张三');
      expect(json['scores'], {'数学': 95, '英语': 88});
    });

    test('fromJson 反序列化', () {
      final json = {
        'student_id': '2024001',
        'name': '张三',
        'scores': {'数学': 95, '英语': 88},
      };

      final student = StudentData.fromJson(json);

      expect(student.studentId, '2024001');
      expect(student.name, '张三');
      expect(student.scores['数学'], 95);
      expect(student.scores['英语'], 88);
    });

    test('fromJson 处理缺失字段', () {
      final student = StudentData.fromJson({});

      expect(student.studentId, '');
      expect(student.name, '');
      expect(student.scores, {});
    });

    test('fromJson 处理 null scores', () {
      final json = {
        'student_id': '2024001',
        'name': '张三',
        'scores': null,
      };

      final student = StudentData.fromJson(json);

      expect(student.studentId, '2024001');
      expect(student.scores, {});
    });

    test('fromJson 处理非 Map scores', () {
      final json = {
        'student_id': '2024001',
        'name': '张三',
        'scores': 'invalid',
      };

      final student = StudentData.fromJson(json);

      expect(student.scores, {});
    });

    test('toJson / fromJson 往返（含中文）', () {
      final original = StudentData(
        studentId: '2024002',
        name: '李四',
        scores: {'语文': 92, '数学': 85, '英语': 78, '物理': 90},
      );

      final json = original.toJson();
      final restored = StudentData.fromJson(json);

      expect(restored.studentId, original.studentId);
      expect(restored.name, original.name);
      expect(restored.scores.length, original.scores.length);
      expect(restored.scores['语文'], 92);
    });

    test('空成绩列表', () {
      final student = StudentData(studentId: '2024003', name: '王五');
      expect(student.scores, {});
      expect(student.scores.isEmpty, isTrue);
    });
  });
}
