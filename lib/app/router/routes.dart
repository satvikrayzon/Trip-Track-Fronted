abstract final class AppPaths {
  static const splash = '/splash';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const home = '/home';
  static const userHome = '/user/home';
  static const adminDashboard = '/admin/dashboard';
  static const managerHome = '/manager/home';
  static const adminUserList = '/admin/user-list';
  static const adminCreateUser = '/admin/create-user';
  static const adminTravelRequests = '/admin/travel-requests';
  static const adminFuelRates = '/admin/fuel-rates';
  static const liveMap = '/admin/live-map';
  static const tripDetail = '/trip/:id';
  static String trip(String id) => '/trip/$id';
  static const legacyTripDetail = '/user/request-details';
  static const createTrip = '/trips/create';
  static const tripList = '/trips';
  static const camera = '/camera';
  static const settings = '/settings';
  static const profile = '/profile';
}
