import 'dart:async';



import 'package:flutter/foundation.dart';



import '../../../../core/app_messenger.dart';

import '../../../../core/di/service_locator.dart';

import '../../../../core/network/models/api_result.dart';

import '../../../../core/theme/app_colors.dart';

import '../../../auth/data/datasources/users_remote_datasource.dart';

import '../../../auth/data/models/user_model.dart';

import '../../../auth/presentation/controllers/app_auth_controller.dart';



/// Admin user list — polls `/users`.

class AdminUserListController {

  AdminUserListController({

    UsersRemoteDataSource? usersApi,

    AppAuthController? authController,

  })  : _usersApi = usersApi ?? ServiceLocator.I.get(),

        _authController = authController ?? ServiceLocator.I.get();



  final UsersRemoteDataSource _usersApi;

  final AppAuthController _authController;



  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  final ValueNotifier<List<UserModel>> users =

      ValueNotifier<List<UserModel>>([]);

  final ValueNotifier<String> searchQuery = ValueNotifier<String>('');

  final ValueNotifier<String> filterRole = ValueNotifier<String>('all');

  final ValueNotifier<String> filterStatus = ValueNotifier<String>('all');



  List<UserModel> _allUsers = [];

  Timer? _pollTimer;



  void start() {

    if (!_authController.isAdmin) return;

    unawaited(_startAfterSessionReady());

    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) {

      if (!_authController.isAdmin) return;

      unawaited(_load());

    });

  }



  void dispose() {

    _pollTimer?.cancel();

    isLoading.dispose();

    users.dispose();

    searchQuery.dispose();

    filterRole.dispose();

    filterStatus.dispose();

  }



  Future<void> _startAfterSessionReady() async {

    await _authController.ensureSessionReady();

    if (!_authController.isAdmin) return;

    await _load();

  }



  Future<void> _load() async {

    if (!_authController.isAdmin) return;

    try {

      isLoading.value = true;

      final result = await _usersApi.listUsers();

      switch (result) {

        case ApiSuccess(:final data):

          _allUsers = data;

          _applyFilters();

        case ApiFailure():

          break;

      }

    } catch (e) {


    } finally {

      isLoading.value = false;

    }

  }



  void searchUsers(String query) {

    searchQuery.value = query.toLowerCase();

    _applyFilters();

  }



  void filterByRole(String role) {

    filterRole.value = role;

    _applyFilters();

  }



  void filterByStatus(String status) {

    filterStatus.value = status;

    _applyFilters();

  }



  void _applyFilters() {

    var filtered = List<UserModel>.from(_allUsers);



    if (filterRole.value != 'all') {

      filtered =

          filtered.where((user) => user.role == filterRole.value).toList();

    }



    if (filterStatus.value != 'all') {

      filtered = filtered

          .where((user) => user.status == filterStatus.value)

          .toList();

    }



    if (searchQuery.value.isNotEmpty) {

      filtered = filtered.where((user) {

        return user.name.toLowerCase().contains(searchQuery.value) ||

            user.email.toLowerCase().contains(searchQuery.value) ||

            user.employeeCode.toLowerCase().contains(searchQuery.value);

      }).toList();

    }



    users.value = filtered;

  }



  Future<void> refresh() => _load();



  Future<void> banUser(UserModel user) async {

    try {

      if (user.uid == _authController.currentUserData?.uid) {

        showAppSnackBar(

          title: 'Error',

          message: 'You cannot ban yourself',

          backgroundColor: AppColors.error,

        );

        return;

      }



      final r = await _usersApi.deactivateUser(user.uid);

      switch (r) {

        case ApiSuccess():

          showAppSnackBar(

            title: 'Success',

            message: '${user.name} has been banned',

            backgroundColor: AppColors.success,

          );

          await _load();

        case ApiFailure(:final failure):

          showAppSnackBar(

            title: 'Error',

            message: failure.message,

            backgroundColor: AppColors.error,

          );

      }

    } catch (e) {


    }

  }



  Future<void> unbanUser(UserModel user) async {

    try {

      final r = await _usersApi.activateUser(user.uid);

      switch (r) {

        case ApiSuccess():

          showAppSnackBar(

            title: 'Success',

            message: '${user.name} has been unbanned',

            backgroundColor: AppColors.success,

          );

          await _load();

        case ApiFailure(:final failure):

          showAppSnackBar(

            title: 'Error',

            message: failure.message,

            backgroundColor: AppColors.error,

          );

      }

    } catch (e) {


    }

  }

}


