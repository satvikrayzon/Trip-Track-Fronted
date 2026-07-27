import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main() async {
  final dirs = ['../lib', '../test', '..'];
  for (final dirPath in dirs) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;
    
    // Only go recursive for lib and test, for the root directory just process files in the root to avoid .dart_tool, build, etc.
    final recursive = dirPath != '..';
    final files = dir.listSync(recursive: recursive).whereType<File>().where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
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
      print('Cleaned ${file.path}');
    }
  }
}

class LogRemoverVisitor extends RecursiveAstVisitor<void> {
  final List<AstNode> nodesToRemove = [];

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
      if (thenStmt is ExpressionStatement && _isLogStatement(thenStmt.expression)) {
        if (node.elseStatement == null) {
          nodesToRemove.add(node);
          return;
        }
      } else if (thenStmt is Block && thenStmt.statements.length == 1) {
        final innerStmt = thenStmt.statements.first;
        if (innerStmt is ExpressionStatement && _isLogStatement(innerStmt.expression)) {
          if (node.elseStatement == null) {
            nodesToRemove.add(node);
            return;
          }
        }
      }
    }
    super.visitIfStatement(node);
  }

  bool _isLogStatement(Expression expr) {
    if (expr is MethodInvocation) {
      final target = expr.target;
      final methodName = expr.methodName.name;
      
      if (target == null && methodName == 'print') return true;
      if (target == null && methodName == 'debugPrint') return true;
      
      if (target != null && target is Identifier && target.name == 'AppDebugLog') {
        if (methodName.startsWith('log')) return true;
      }
    }
    return false;
  }
}
