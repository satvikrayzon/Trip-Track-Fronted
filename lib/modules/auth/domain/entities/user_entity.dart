/// User entity for domain layer
class UserEntity {
  final String uid;
  final String email;
  final String name;
  final String employeeCode;
  final String role;
  final String mobile;
  final String sitingLocation;
  final String? reportingManagerId;
  final String? reportingManagerName;

  const UserEntity({
    required this.uid,
    required this.email,
    required this.name,
    required this.employeeCode,
    required this.role,
    this.mobile = '',
    this.sitingLocation = '',
    this.reportingManagerId,
    this.reportingManagerName,
  });

  @override
  String toString() {
    return 'UserEntity(uid: $uid, email: $email, name: $name, employeeCode: $employeeCode, role: $role, mobile: $mobile)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserEntity &&
        other.uid == uid &&
        other.email == email &&
        other.name == name &&
        other.employeeCode == employeeCode &&
        other.role == role &&
        other.mobile == mobile &&
        other.sitingLocation == sitingLocation &&
        other.reportingManagerId == reportingManagerId &&
        other.reportingManagerName == reportingManagerName;
  }

  @override
  int get hashCode {
    return uid.hashCode ^
        email.hashCode ^
        name.hashCode ^
        employeeCode.hashCode ^
        role.hashCode ^
        mobile.hashCode ^
        sitingLocation.hashCode ^
        reportingManagerId.hashCode ^
        reportingManagerName.hashCode;
  }
}
