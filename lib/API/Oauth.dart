// Oauth.dart

import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'globals.dart' as globals;
import 'constants.dart';
import 'token.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

///===========================================
/// Class related to Authorization processs
///===========================================
abstract class Auth {
  StreamController<String> onCodeReceived = StreamController();

// Save the token and the expiry date
  Future<void> saveToken(String token, int expire, String scope) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('token', token);
    prefs.setInt('expire', expire); // Stored in seconds
    prefs.setString('scope', scope);

    // Save also in globals to get direct access
    globals.token.accessToken = token;
    globals.token.scope = scope;
    globals.token.expiresAt =expire;

    print('token saved!!!');
  }

// Get the stored token and expiry date
  Future<Token> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    var localToken = Token();
    print('---> Entering getStoredToken');

    try {
      localToken.accessToken = prefs.getString('token').toString();
      localToken.expiresAt = prefs.getInt('expire');
      localToken.scope = prefs.getString('scope');

      // load the data in globals 
      globals.token.accessToken =localToken.accessToken;
      globals.token.expiresAt =localToken.expiresAt;
      globals.token.scope =localToken.scope;
    } catch (error) {
      print('---> Error getting the key');
      localToken.accessToken = null;
      localToken.expiresAt = null;
      localToken.scope = null;
    }

    if (localToken.expiresAt != null) {
      var dateExpired =
          DateTime.fromMillisecondsSinceEpoch(localToken.expiresAt);
      var disp = dateExpired.day.toString() + '/' +
          dateExpired.month.toString() + '/' +
          dateExpired.hour.toString();

      globals.displayInfo('stored token ${localToken.accessToken}  expires: $disp ');
    }

    return (localToken);
  }

  Map<String, String> createHeader() {
    var _token =  globals.token;
    if (_token != null) {
      return {'Authorization': 'Bearer ${_token.accessToken}'};
    } else {
      return {null: null};
    }
  }

  // Get the code from Strava server
  Future<void> getStravaCode(
      String clientID, String redirectUrl, String scope) async {
    print('Welcome to getStravaCode');
    var code = "";
    var params = '?' +
        'client_id=' +
        clientID +
        '&redirect_uri=' +
        redirectUrl +
        '&response_type=' +
        'code' +
        '&approval_prompt=' +
        'auto' +
        '&scope=' +
        scope;

    var reqAuth = authorizationEndpoint + params;
    print('---> $reqAuth');

    closeWebView();
    launch(reqAuth,
        forceWebView: true, forceSafariVC: true, enableJavaScript: true);

    // Launch small http server to collect the answer from Strava
    //------------------------------------------------------------
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 8080, shared: true);
    server.listen((HttpRequest request) async {
      //  server.listen((HttpRequest request)  {
      // Get the answer from Strava
      final uri = request.uri;

      code = uri.queryParameters["code"];
      final error = uri.queryParameters["error"];
      request.response.close();
      print('---> code $code, error $error');

      closeWebView();
      server.close(force: true);

      onCodeReceived.add(code);

      print('---> Get the new code $code');
    });
  }

  /// Do Strava Authentication. 
  /// 
  /// Do not do/show the Strava login if a token has been stored previously
  /// and is not expired
  /// Do/show the Strava login if the scope has been changed since last storage of the token
  /// return true if no problem in authentication has been found
  Future<bool> OAuth(
      String clientID, String redirectUrl, String scope, String secret) async {
    print('Welcome to Oauth');
    bool isAuthOk = false;
    bool isExpired = true;


    final Token tokenStored = await getStoredToken();
    final String _token = tokenStored.accessToken;

     // Check if the token is not expired
    if (_token != "null") {
      print('----> token has been stored before! ${tokenStored.accessToken}');

      isExpired = isTokenExpired(tokenStored);
      print('----> isExpired $isExpired');
    }


   // Check if the scope has changed
    if ((tokenStored.scope != scope) || (_token == "null") || isExpired) {
      // Ask for a new authorization
      print('---> Doing a new authorization');
      isAuthOk = await newAuthorization(clientID, redirectUrl, secret, scope);
    } else {
      isAuthOk = true;
    }

    return isAuthOk;
  }


Future<bool> newAuthorization(
      String clientID, String redirectUrl, String secret, String scope) async {
    
    bool returnValue = false;

    await getStravaCode(clientID, redirectUrl, scope);

     var stravaCode = await onCodeReceived.stream.first;

    if (stravaCode != null) {
      var answer = await getStravaToken(clientID, secret, stravaCode);

      print('---> answer ${answer.expiresAt}  , ${answer.accessToken}');

      // Save the token information
      if (answer.accessToken != null && answer.expiresAt != null) {
        await saveToken(answer.accessToken, answer.expiresAt, scope);
        returnValue = true;
      }
    } else {
      print('----> code is still null');
    }
    return returnValue;
  }



  Future<Token> getStravaToken(
      String clientID, String secret, String code) async {
    Token _answer = Token();

    print('---> Entering getStravaToken!!');
    var urlToken = tokenEndpoint +
        '?client_id=' +
        clientID +
        '&client_secret=' +
        secret + // Put your own secret in secret.dart
        '&code=' +
        code +
        '&grant_type=' +
        'authorization_code';

    print('----> urlToken $urlToken');

    var value = await http.post(urlToken);

    // responseToken.then((value) {
    print('----> body ${value.body}');

    if (value.body.contains('message')) {
      // This is not the normal message
      print('---> Error in getStravaToken');
      // will return _answer null
    } else {
      var tokenBody = json.decode(value.body);
      // Todo: handle error with message "Authorization Error" and errors != null
      var _body = Token.fromJson(tokenBody);
      var accessToken = _body.accessToken;
      var refreshToken = _body.refreshToken;
      var expiresAt = _body.expiresAt * 1000;

      _answer.accessToken = accessToken;
      _answer.refreshToken = refreshToken;
      _answer.expiresAt = expiresAt;
    }

    return (_answer);
    // });
  }

  bool isTokenExpired(Token token) {
    final DateTime _expiryDate =
        DateTime.fromMillisecondsSinceEpoch(token.expiresAt);
    return (_expiryDate.isBefore(DateTime.now()));
  }

/*******

  Future<bool> OAuth(
      String clientID, String redirectUrl, String scope, String secret) async {
    bool isExpired = true;
    bool isAuthOK = false;

    final Token tokenStored = await getStoredToken();
    final String _token = tokenStored.accessToken;

    // Check if the token is not expired
    if (_token != "null") {
      print('----> token has been stored before! ${tokenStored.accessToken}');

      isExpired = isTokenExpired(tokenStored);
      print('----> isExpired $isExpired');
    }

    // Check if the scope has changed
    if ((tokenStored.scope != scope) || (_token == "null") || isExpired) {
      // Ask for a new authorization
      print('---> Doing a new authorization');
      isAuthOK = await newAuthorization(clientID, redirectUrl, secret, scope);
    } else {
      isAuthOK = true;
    }

    return isAuthOK;
  }
*****/
  

  Future<void> deAuthorize() async {
    String returnValue;

    var _token = await getStoredToken();

    var _header =  createHeader();
    if (_header != null) {
      final reqDeAuthorize = "https://www.strava.com/oauth/deauthorize";
      var rep = await http.post(reqDeAuthorize, headers: _header);
      if (rep.statusCode == 200) {
        print('DeAuthorize done');
        await saveToken(null, null, null);
      } else {
        print('problem in deAuthorize request');
        // Todo add an error code
      }
    }
  }
}