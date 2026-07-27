import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  try {
    final res = await dio.get('http://localhost:3000/api/trips/summary');
  } catch(e) {
  }
}
