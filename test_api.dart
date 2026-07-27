import "package:dio/dio.dart";
void main() async {
  final dio = Dio();
  try {
    final res = await dio.get("http://localhost:3000/api/travel-requests?page=1&limit=100&mine=false");
  } catch (e) {
    if (e is DioException) {
    } else {
    }
  }
}
