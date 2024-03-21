import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kreki119/app/core/base/base_controller.dart';
import 'package:kreki119/app/data/local/preference/preference_manager.dart';
import 'package:kreki119/app/data/model/form/Form_update_profile.dart';
import 'package:kreki119/app/data/model/response/base_response.dart';
import 'package:kreki119/app/data/model/response/volunteer_mobile.dart';
import 'package:kreki119/app/modules/main/controllers/main_controller.dart';
import 'package:kreki119/app/modules/main/model/menu_code.dart';
import 'package:kreki119/app/routes/app_pages.dart';
import 'package:logger/logger.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../flavors/build_config.dart';
import '../../../core/model/emergency_status.dart';
import '../../../core/model/page_state.dart';
import '../../../core/model/volunteer_status.dart';
import '../../../core/utils/debouncer.dart';
import '../../../data/model/response/contact_entity.dart';
import '../../../data/model/response/emergency_mobile_entity.dart';
import '../../../data/model/response/user_mobile_entity.dart';
import '../../../data/repository/emergency/emergency_repository.dart';
import '../../../data/repository/volunteer/volunteer_repository.dart';
import '../../../data/services/storage/util_storage.dart';
import '../../../network/exceptions/api_exception.dart';
import '../../../network/exceptions/app_exception.dart';
import '../../../network/exceptions/json_format_exception.dart';
import '../../../network/exceptions/network_exception.dart';
import '../../../network/exceptions/not_found_exception.dart';
import '../../../network/exceptions/service_unavailable_exception.dart';
import '../../../network/exceptions/unauthorize_exception.dart';
import '../../home/model/aid_book.dart';

class ProfileController extends BaseController {

  final mainController = Get.find<MainController>();


  final _packageName = ''.obs;
  String get packageName => _packageName.value;

  late final DeviceInfoPlugin deviceInfo;

  dynamic callDataService<T>(
      Future<T> future, {
        Function(Exception exception)? onError,
        Function(T response)? onSuccess,
        Function? onStart,
        Function? onComplete,
      }) async {
    Exception? _exception;

    onStart == null ? showLoading() : onStart();

    try {
      final T response = await future;

      if (onSuccess != null) onSuccess(response);

      onComplete == null ? hideLoading() : onComplete();
      updatePageState(PageState.SUCCESS);

      return response;
    } on ServiceUnavailableException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on UnauthorizedException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on TimeoutException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message ?? 'Timeout exception');
    } on NetworkException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on JsonFormatException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on NotFoundException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on SocketException catch (exception){
      _exception = exception;
      showErrorMessage(exception.osError?.message ?? exception.message);
    } on HandshakeException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on ApiException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } on AppException catch (exception) {
      _exception = exception;
      showErrorMessage(exception.message);
    } catch (error) {
      _exception = AppException(message: "$error");
      logger.e("Controller>>>>>> error $error");
      showErrorMessage(error.toString());
    }

    updatePageState(PageState.FAILED);

    if (onError != null) onError(_exception);

    onComplete == null ? hideLoading() : onComplete();
  }

  checkVolunteerStatus() async{
    var user = await getUserMobile();
    callDataService(volunteerRepository.getVolunteerById(user.id.toString()),
        onSuccess: (response)async{
          var data = response.data;
          if(data==null){
            showConfirmDialog(Get.context, 'Anda belum jadi relawan, lanjutkan mendaftar?',
                positiveText: 'Ya, lanjutkan',
                negativeText: 'Tidak',
                onAccept: (){
                  Get.toNamed(Routes.UPGRADE_VOLUNTEER);
                }
            );
          } else {
            if(data.status == VolunteerStatus.WAITING.name){
              showMessage('Pengajuan Volunteer dalam tahap verifikasi admin');
            } else if(data.status == VolunteerStatus.ACCEPTED.name){
              if(mainController.userRole.group == 'user'){
                await mainController.loadProfile();
              }
              Get.toNamed(Routes.VOLUNTEER);
            } else if (data.status == VolunteerStatus.DEACTIVATED.name){
              showErrorMessage('Status volunteer tidak aktif, hubungi admin untuk info lebih lanjut');
            } else if(data.status == VolunteerStatus.REJECTED.name){
              showErrorMessage('Pengajuan Volunteer tidak di setujui admin');
            }
          }
        }
    );

  }
  @override
  void onInit() async{
    super.onInit();

    deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    _packageName.value = packageInfo.version;

    mainController.loadProfile();
    mainController.loadProfile();
    loadDataContact();
    setUserMobile(await mainController.getUserMobile());
    await mainController.onLoadEmergency();
    await mainController.loadProfile();
    await loadUpdateLocation();
    super.onInit();
    _packageName.value = packageInfo.version;
    await mainController.loadUpdateLocation();

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (message.notification != null) {
        //TODO
      }
    });

  }
  loadDataContact()async{
    callDataService(userRepo.getContacts(),
        onSuccess: (response){
          var data = response.data;

          if(data != null){
            contacts = data;
          }
        }
    );
  }


  @override
  void onReady() {
    super.onReady();
  }

  @override
  void onClose() {
    //TODO
  }

  onSignOut()async{
    await preferenceManager.setString(PreferenceManager.keyToken, '');
    await preferenceManager.setString(PreferenceManager.keyUser, '');
    await preferenceManager.setString(PreferenceManager.keyRole, '');

    mainController.onMenuSelected(MenuCode.HOME);

    Get.offAllNamed(Routes.SIGN_IN);
  }

  updatePassword(String pass) {
    finish(Get.context!);
    callDataService(authRepo.updatePassword(pass),
      onSuccess: (response){
        if(response.code==null){
          if(response.code! >= 300){
            showErrorMessage("Failed: ${response.message}");
          }

          return;
        }

        showMessage("${response.message}");
      }
    );
  }

  onChooseImage()async{
    var image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if(image == null) return;

    showLoading();
    var user = await getUserMobile();
    var upload = await UtilStorage.uploadProfileImage(image.path, user.id.toString());

    upload.snapshotEvents.listen((event) async{
      switch(event.state){
        case TaskState.paused:
          showMessage('Upload pause');
          hideLoading();
          break;
        case TaskState.running:
          var progress = event.bytesTransferred / event.totalBytes;
          logger.d('progress: ${progress*100}');
          break;
        case TaskState.success:
          var url = await event.ref.getDownloadURL();
          updateProfilePhoto(url);
          hideLoading();
          break;
        case TaskState.canceled:
          hideLoading();
          break;
        case TaskState.error:
          showErrorMessage('Error, Failed to upload try again later');
          hideLoading();
          break;
      }
    });
  }

  updateProfilePhoto(String url){
    FormUpdateProfile form = FormUpdateProfile()..photo = url;
    callDataService(authRepo.updateProfile(form),
      onSuccess: (response)async{

        if(response.code! >=200 && response.code! < 300){
          mainController.loadProfile();
          showMessage('${response.message}');
        }else {
          if(response.message==null) return;
          showErrorMessage('${response.message}');
        }

      }
    );
  }

}
final mainController = Get.find<MainController>();
final EmergencyRepository emergencyRepository =
Get.find(tag: (EmergencyRepository).toString());
final RxList<EmergencyMobileEntity> _finishedController = RxList.empty();
List<EmergencyMobileEntity> get finishedList => _finishedController.toList();
final _aidBooks = RxList<AidBook>.empty();
List<AidBook> get aidBooks => _aidBooks.toList();
final Logger logger = BuildConfig.instance.config.logger;
final _playMode = PlayerState.stopped.obs;
PlayerState get playMode => _playMode.value;
setPlayerState(PlayerState state) => _playMode.value = state;
final PreferenceManager preferenceManager = Get.find(tag: (PreferenceManager).toString());
final VolunteerRepository volunteerRepository = Get.find(tag: (VolunteerRepository).toString());
final _packageName = ''.obs;
String get packageName => _packageName.value;
final _contact = RxList<ContactEntity>();
List<ContactEntity> get contacts => _contact.toList();
final _userMobile = UserMobileEntity().obs;
UserMobileEntity get userMobile => _userMobile.value;
set contacts(List<ContactEntity> data) => _contact(data);
setUserMobile(UserMobileEntity val) => _userMobile.value =val;
late TabController tabController;


final _errorMessageController = ''.obs;
String get errorMessage => _errorMessageController.value;
showErrorMessage(String msg) {
  _errorMessageController(msg);
  Debouncer().run(() {
    _errorMessageController('');
  });
}
final _messageController = ''.obs;
showMessage(String msg) {
  _messageController(msg);

  Debouncer().run(() {
    _messageController('');
  });
}

Future<UserMobileEntity> getUserMobile() async{
  var user = await preferenceManager.getString(PreferenceManager.keyUser);
  var userMap = json.decode(user);
  logger.d('user: $userMap');
  var userMobile = UserMobileEntity.fromJson(userMap);

  return userMobile;
}





