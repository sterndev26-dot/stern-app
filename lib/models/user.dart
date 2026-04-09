import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

enum UserType { technician, cleaner, undefined }

class User {
  static final User _instance = User._internal();
  factory User() => _instance;
  User._internal();

  static User get instance => _instance;

  UserType _userType = UserType.undefined;

  UserType get userType => _userType;

  bool get isTechnician => _userType == UserType.technician;
  bool get isCleaner => _userType == UserType.cleaner;

  Future<void> loginAsTechnician() async {
    _userType = UserType.technician;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.sharedUserType, 'TECHNICIAN');
  }

  Future<void> loginAsCleaner() async {
    _userType = UserType.cleaner;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.sharedUserType, 'CLEANER');
  }

  Future<void> logOut() async {
    _userType = UserType.undefined;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.sharedUserType);
  }

  Future<bool> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConstants.sharedUserType);
    if (saved == 'TECHNICIAN') {
      _userType = UserType.technician;
      return true;
    } else if (saved == 'CLEANER') {
      _userType = UserType.cleaner;
      return true;
    }
    return false;
  }
}
