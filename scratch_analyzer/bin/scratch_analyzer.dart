import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main() async {
  final dirs = ['../lib'];
  for (final dirPath in dirs) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      // Skip dedicated debug utilities — deleted separately.
      final name = file.uri.pathSegments.last;
      if (name == 'app_debug_log.dart' || name == 'travel_request_debug_log.dart') {
        continue;
      }

      final content = file.readAsStringSync();
      final result = parseString(
        content: content,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );

      final visitor = LogRemoverVisitor();
      result.unit.visitChildren(visitor);

      if (visitor.nodesToRemove.isEmpty) continue;

      visitor.nodesToRemove.sort((a, b) => b.offset.compareTo(a.offset));

      String newContent = content;
      for (final node in visitor.nodesToRemove) {
        int start = node.offset;
        int end = node.end;

        int lineStart = start;
        while (lineStart > 0 && newContent[lineStart - 1] != '\n') {
          if (newContent[lineStart - 1].trim().isNotEmpty) {
            break;
          }
          lineStart--;
        }

        if (lineStart < start) {
          int lineEnd = end;
          while (lineEnd < newContent.length && newContent[lineEnd] != '\n') {
            if (newContent[lineEnd].trim().isNotEmpty) {
              break;
            }
            lineEnd++;
          }

          if ((lineStart == 0 || newContent[lineStart - 1] == '\n') &&
              (lineEnd == newContent.length || newContent[lineEnd] == '\n')) {
            start = lineStart;
            end = lineEnd < newContent.length ? lineEnd + 1 : lineEnd;
          }
        }

        newContent = newContent.substring(0, start) + newContent.substring(end);
      }

      file.writeAsStringSync(newContent);
      stdout.writeln('Cleaned ${file.path}');
    }
  }
}

class LogRemoverVisitor extends RecursiveAstVisitor<void> {
  final List<AstNode> nodesToRemove = [];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (name == '_roadAlignLog') {
      nodesToRemove.add(node);
      return;
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    if (_isLogStatement(node.expression)) {
      nodesToRemove.add(node);
      return;
    }
    super.visitExpressionStatement(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    final condition = node.expression;
    if (condition is SimpleIdentifier && condition.name == 'kDebugMode') {
      final thenStmt = node.thenStatement;
      if (_thenIsOnlyLog(thenStmt) && node.elseStatement == null) {
        nodesToRemove.add(node);
        return;
      }
    }
    // Empty kDebugMode blocks left after prior cleanup.
    if (condition is BinaryExpression &&
        condition.operator.type.lexeme == '&&' &&
        _containsKDebugMode(condition) &&
        node.elseStatement == null) {
      final thenStmt = node.thenStatement;
      if (thenStmt is Block && thenStmt.statements.isEmpty) {
        nodesToRemove.add(node);
        return;
      }
      if (_thenIsOnlyLog(thenStmt)) {
        nodesToRemove.add(node);
        return;
      }
    }
    super.visitIfStatement(node);
  }

  bool _containsKDebugMode(Expression expr) {
    if (expr is SimpleIdentifier && expr.name == 'kDebugMode') return true;
    if (expr is BinaryExpression) {
      return _containsKDebugMode(expr.leftOperand) ||
          _containsKDebugMode(expr.rightOperand);
    }
    return false;
  }

  bool _thenIsOnlyLog(Statement thenStmt) {
    if (thenStmt is ExpressionStatement && _isLogStatement(thenStmt.expression)) {
      return true;
    }
    if (thenStmt is Block) {
      if (thenStmt.statements.isEmpty) return true;
      if (thenStmt.statements.length == 1) {
        final inner = thenStmt.statements.first;
        if (inner is ExpressionStatement && _isLogStatement(inner.expression)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isLogStatement(Expression expr) {
    if (expr is MethodInvocation) {
      final target = expr.target;
      final methodName = expr.methodName.name;

      if (target == null && methodName == 'print') return true;
      if (target == null && methodName == 'debugPrint') return true;
      if (target == null && methodName == '_roadAlignLog') return true;

      if (target is Identifier) {
        final t = target.name;
        if (t == 'AppDebugLog' && methodName.startsWith('log')) return true;
        if (t == 'TravelRequestDebugLog' && methodName.startsWith('log')) {
          return true;
        }
      }
    }
    return false;
  }
}
