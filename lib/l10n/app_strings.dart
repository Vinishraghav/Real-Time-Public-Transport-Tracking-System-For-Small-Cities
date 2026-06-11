import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class AppStrings {
  AppStrings._(this.language);

  final String language;

  bool get isTamil => language.toLowerCase().startsWith('tamil');

  static AppStrings of(BuildContext context, {bool listen = true}) {
    final language = listen
        ? context.select<AuthProvider, String>(
            (auth) => auth.session?.language ?? 'English',
          )
        : context.read<AuthProvider>().session?.language ?? 'English';
    return AppStrings._(language);
  }

  static String translateForLanguage(
    String language,
    String key, {
    Map<String, String> params = const {},
  }) {
    final strings = language.toLowerCase().startsWith('tamil')
        ? _tamil
        : _english;
    var value = strings[key] ?? _english[key] ?? key;
    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  String t(String key, {Map<String, String> params = const {}}) {
    return translateForLanguage(language, key, params: params);
  }

  static const Map<String, String> _english = {
    'welcome_to': 'Welcome to',
    'login_description':
        'Drivers sign in with bus number and password. Passengers can continue with Google or email.',
    'bus_number': 'Bus Number',
    'login_as_driver': 'Login as Driver',
    'continue_as_passenger': 'Continue as Passenger',
    'driver_login': 'Driver Login',
    'enter_password': 'Enter password',
    'cancel': 'Cancel',
    'continue': 'Continue',
    'passenger_login': 'Passenger Login',
    'create_passenger_account': 'Create Passenger Account',
    'full_name': 'Full name',
    'email_address': 'Email address',
    'password': 'Password',
    'create_account': 'Create Account',
    'login': 'Login',
    'continue_with_google': 'Continue with Google',
    'already_have_account': 'Already have an account? Sign in',
    'need_account': 'Need an account? Register',
    'account_preferences': 'Account & Preferences',
    'edit_profile': 'Edit Profile',
    'set_display_name': 'Set your display name',
    'dark_mode': 'Dark Mode',
    'switch_appearance': 'Switch the app appearance',
    'language': 'Language',
    'application_settings': 'Application Settings',
    'location_services': 'Location Services',
    'access_granted': 'Access granted',
    'access_denied': 'Access denied',
    'push_notifications': 'Push Notifications',
    'stay_updated': 'Stay updated on bus arrivals',
    'data_saver': 'Data Saver',
    'reduce_refresh_scope': 'Reduce location/network refresh scope',
    'support_info': 'Support & Info',
    'about_citybus': 'About CityBus Live',
    'logout': 'Log Out',
    'sign_out_current': 'Sign out of current session',
    'select_language': 'Select Language',
    'save': 'Save',
    'about_version': 'Version 1.0.0',
    'alerts_notifications': 'Alerts & Notifications',
    'unread_alerts': '{count} Unread Alerts',
    'clear_all': 'Clear All',
    'no_active_alerts': 'No active alerts',
    'caught_up': "You're all caught up on notifications!",
    'just_now': 'Just now',
    'mins_ago': '{count}m ago',
    'hours_ago': '{count}h ago',
    'days_ago': '{count}d ago',
    'driver_mode': 'Driver Mode',
    'passenger_mode': 'Passenger Mode',
    'nearby_buses_active': '{count} nearby buses active',
    'trip_active': 'Trip Active',
    'trip_paused': 'Trip Paused',
    'trip_ended': 'Trip Ended',
    'no_active_trip': 'No Active Trip',
    'view_live_map': 'View Live Map',
    'trip_management': 'Trip Management',
    'trip_time': 'Trip Time',
    'current_next': 'Current: {current} -> Next: {next}',
    'start_trip': 'Start Trip',
    'pause_trip': 'Pause Trip',
    'resume_trip': 'Resume Trip',
    'end_trip': 'End Trip',
    'find_destination': 'Find Your Destination',
    'enter_destination_stop': 'Enter destination stop...',
    'search': 'Search',
    'search_stops_routes': 'Search stops or routes...',
    'route_not_found': 'Route not found',
    'go_back': 'Go Back',
    'no_stops_configured': 'No stops configured for this route.',
    'origin': 'Origin',
    'destination': 'Destination',
    'ride_confirmed': 'Ride Confirmed',
    'tracking_bus_to': 'Tracking Bus {busId} to {destination}.',
    'passenger_waiting_ahead': 'Passenger Waiting Ahead',
    'passenger_waiting_message': '{passenger} is waiting to ride near {stop}.',
    'route_deviation': 'Route Deviation',
    'route_deviation_message':
        'You are {distance}m away from the planned route.',
    'delay_warning': 'Delay Warning',
    'delay_warning_message':
        'Bus speed is low. Passengers may see a delay warning.',
    'bus_delayed': 'Bus Delayed',
    'bus_delayed_message': 'Bus {busId} is currently paused.',
    'bus_approaching_stop': 'Bus Approaching Stop',
    'bus_approaching_message': 'Bus {busId} is within 100m of {destination}.',
    'bus_arrived': 'Bus Arrived',
    'bus_arrived_message': 'Bus {busId} has arrived at {destination}.',
    'stop_not_found': 'Stop not found. Check spelling.',
    'search_failed': 'Search failed: {error}',
    'init_failed': 'Init failed: {error}',
    'session_restore_failed': 'Session restore failed: {error}',
  };

  static const Map<String, String> _tamil = {
    'welcome_to': 'வரவேற்கிறோம்',
    'login_description':
        'டிரைவர்கள் பஸ் நம்பர் மற்றும் பாஸ்வேர்ட் கொண்டு உள்நுழையலாம். பயணிகள் Google அல்லது email மூலம் தொடரலாம்.',
    'bus_number': 'பஸ் நம்பர்',
    'login_as_driver': 'டிரைவராக உள்நுழை',
    'continue_as_passenger': 'பயணியாக தொடரவும்',
    'driver_login': 'டிரைவர் உள்நுழைவு',
    'enter_password': 'பாஸ்வேர்ட் உள்ளிடவும்',
    'cancel': 'ரத்து',
    'continue': 'தொடரவும்',
    'passenger_login': 'பயணி உள்நுழைவு',
    'create_passenger_account': 'பயணி கணக்கு உருவாக்கவும்',
    'full_name': 'முழு பெயர்',
    'email_address': 'மின்னஞ்சல் முகவரி',
    'password': 'கடவுச்சொல்',
    'create_account': 'கணக்கு உருவாக்கவும்',
    'login': 'உள்நுழை',
    'continue_with_google': 'Google மூலம் தொடரவும்',
    'already_have_account': 'ஏற்கனவே கணக்கு உள்ளதா? உள்நுழைக',
    'need_account': 'கணக்கு வேண்டுமா? பதிவு செய்யவும்',
    'account_preferences': 'கணக்கு மற்றும் விருப்பங்கள்',
    'edit_profile': 'சுயவிவரம் திருத்து',
    'set_display_name': 'காட்சிப் பெயர் அமைக்கவும்',
    'dark_mode': 'டார்க் மோடு',
    'switch_appearance': 'அப்பின் தோற்றத்தை மாற்றவும்',
    'language': 'மொழி',
    'application_settings': 'அப்பிளிக்கேஷன் அமைப்புகள்',
    'location_services': 'இடம் சேவைகள்',
    'access_granted': 'அனுமதி வழங்கப்பட்டது',
    'access_denied': 'அனுமதி மறுக்கப்பட்டது',
    'push_notifications': 'அறிவிப்புகள்',
    'stay_updated': 'பஸ் வருகை தகவல்களை உடனுக்குடன் பெறுங்கள்',
    'data_saver': 'டேட்டா சேவர்',
    'reduce_refresh_scope': 'இடம் / நெட்வொர்க் புதுப்பிப்பை குறைக்கவும்',
    'support_info': 'உதவி மற்றும் தகவல்',
    'about_citybus': 'CityBus Live பற்றி',
    'logout': 'வெளியேறு',
    'sign_out_current': 'தற்போதைய அமர்விலிருந்து வெளியேறு',
    'select_language': 'மொழியை தேர்ந்தெடுக்கவும்',
    'save': 'சேமிக்கவும்',
    'about_version': 'பதிப்பு 1.0.0',
    'alerts_notifications': 'அறிவிப்புகள்',
    'unread_alerts': '{count} படிக்காத அறிவிப்புகள்',
    'clear_all': 'அனைத்தையும் நீக்கு',
    'no_active_alerts': 'செயலில் அறிவிப்புகள் இல்லை',
    'caught_up': 'அனைத்து அறிவிப்புகளும் பார்த்துவிட்டீர்கள்!',
    'just_now': 'இப்போதுதான்',
    'mins_ago': '{count} நிமிடங்கள் முன்',
    'hours_ago': '{count} மணி நேரம் முன்',
    'days_ago': '{count} நாட்கள் முன்',
    'driver_mode': 'டிரைவர் மோடு',
    'passenger_mode': 'பயணி மோடு',
    'nearby_buses_active': '{count} அருகிலுள்ள பேருந்துகள் செயலில் உள்ளன',
    'trip_active': 'பயணம் செயலில் உள்ளது',
    'trip_paused': 'பயணம் இடைநிறுத்தப்பட்டது',
    'trip_ended': 'பயணம் முடிந்தது',
    'no_active_trip': 'செயலில் பயணம் இல்லை',
    'view_live_map': 'நேரடி மேப்பைப் பாருங்கள்',
    'trip_management': 'பயணம் மேலாண்மை',
    'trip_time': 'பயண நேரம்',
    'current_next': 'தற்போது: {current} -> அடுத்தது: {next}',
    'start_trip': 'பயணத்தை தொடங்கு',
    'pause_trip': 'பயணத்தை நிறுத்து',
    'resume_trip': 'பயணத்தை தொடரவும்',
    'end_trip': 'பயணத்தை முடி',
    'find_destination': 'இலக்கை தேடுங்கள்',
    'enter_destination_stop': 'இலக்கு நிறுத்தத்தை உள்ளிடவும்...',
    'search': 'தேடு',
    'search_stops_routes': 'நிறுத்தங்கள் அல்லது ரூட்டுகளை தேடுங்கள்...',
    'route_not_found': 'ரூட்டு கிடைக்கவில்லை',
    'go_back': 'திரும்பிச் செல்',
    'no_stops_configured': 'இந்த ரூட்டிற்கு நிறுத்தங்கள் அமைக்கப்படவில்லை.',
    'origin': 'தொடக்கம்',
    'destination': 'இலக்கு',
    'ride_confirmed': 'பயணம் உறுதிசெய்யப்பட்டது',
    'tracking_bus_to': 'பஸ் {busId} ஐ {destination} வரை கண்காணிக்கிறோம்.',
    'passenger_waiting_ahead': 'முன்னால் பயணி காத்திருக்கிறார்',
    'passenger_waiting_message':
        '{passenger} அவர்கள் {stop} அருகில் காத்திருக்கிறார்.',
    'route_deviation': 'ரூட்டு மாற்றம்',
    'route_deviation_message':
        'திட்டமிட்ட பாதையிலிருந்து {distance} மீட்டர் தூரத்தில் உள்ளீர்கள்.',
    'delay_warning': 'தாமத எச்சரிக்கை',
    'delay_warning_message':
        'பஸ் வேகம் குறைவாக உள்ளது. பயணிகள் தாமத எச்சரிக்கை காணலாம்.',
    'bus_delayed': 'பஸ் தாமதமாக உள்ளது',
    'bus_delayed_message': 'பஸ் {busId} தற்போது இடைநிறுத்தப்பட்டுள்ளது.',
    'bus_approaching_stop': 'பஸ் நிறுத்தத்திற்கு வருகிறது',
    'bus_approaching_message':
        'பஸ் {busId}, {destination} இலிருந்து 100 மீட்டர் அருகில் உள்ளது.',
    'bus_arrived': 'பஸ் வந்துவிட்டது',
    'bus_arrived_message': 'பஸ் {busId}, {destination} சென்றடைந்துவிட்டது.',
    'stop_not_found':
        'நிறுத்தம் கிடைக்கவில்லை. எழுத்துப்பிழை உள்ளதா பாருங்கள்.',
    'search_failed': 'தேடல் தோல்வியடைந்தது: {error}',
    'init_failed': 'தொடக்கம் தோல்வியடைந்தது: {error}',
    'session_restore_failed': 'அமர்வு மீட்பு தோல்வியடைந்தது: {error}',
  };
}

extension AppStringsBuildContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
  AppStrings get l10n => AppStrings.of(this, listen: false);
}
