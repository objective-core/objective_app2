import 'package:flutter/material.dart';
import 'package:objective_app2/utils/routes.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:slider_button/slider_button.dart';
import 'package:walletconnect_secure_storage/walletconnect_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:objective_app2/utils/data.dart';
import 'package:geolocator/geolocator.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  var sessionStorage;
  var _session;

  var data = Data();
  final storage = new FlutterSecureStorage();

  loginUsingMetamask(BuildContext context) async {
    if (!data.connector!.connected) {
      try {
        var session = await data.connector!.createSession(onDisplayUri: (uri) async {
          data.connectionUri = uri;
          await storage.write(key: 'wc-uri', value: uri);
          await launchUrlString(uri, mode: LaunchMode.externalApplication);
        });
              print(session.accounts[0]);
              print(session.chainId);
        setState(() {
          _session = session;
        });
      } catch (exp) {
        print(exp);
      }
    } else {
      _session = data.connector!.session;
      data.connectionUri = await storage.read(key: 'wc-uri');
      print("already connected");
    }
  }

  @override
  Widget build(BuildContext context) {
    print('buiding');
    // spawn a new connector;
    if (data.connector == null) {
      connectToWallet();
    }

    updatePosition();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Page'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/objective_logo.png',
                fit: BoxFit.fitHeight,
                height: 200,
              ),
              (_session != null) ? Container(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account',
                        style: GoogleFonts.merriweather(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${_session.accounts[0]}',
                        style: GoogleFonts.inconsolata(fontSize: 16),
                      ),
                      SizedBox(
                        height: 20,
                      ),
                      Row(
                        children: [
                          Text(
                            'Chain: ',
                            style: GoogleFonts.merriweather(
                              fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              getNetworkName(_session.chainId),
                              style: GoogleFonts.inconsolata(fontSize: 16),
                            )
                        ],
                      ),
                      (_session.chainId != 5)
                      ? Row(
                          children: const [
                            Icon(Icons.warning,
                              color: Colors.redAccent, size: 15),
                            Text('Network not supported. Switch to '),
                            Text(
                              'Goerli Testnet',
                              style:
                                TextStyle(fontWeight: FontWeight.bold),
                            )
                          ],
                        )
                      : Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                              child: Row(
                                children: const [
                                  Icon(Icons.check_circle,
                                    color: Colors.green, size: 15),
                                  Text('Network supported. You are good to go!')
                                ],
                              ),
                            ),
                            SizedBox(height: 10),
                            data.video != null ? Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.pushNamed(context, AppRoutes.signingRoute, arguments: data);
                                },
                                child: const Text('Sign video'),
                              ),
                            ) : Text('To sign video, please record it first.'),
                            SizedBox(height: 10),
                            Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await Navigator.pushNamed(context, AppRoutes.recorderRoute, arguments: data);
                                  setState(() {});
                                },
                                child: const Text('Record video'),
                              ),
                            ),
                            Container(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await Navigator.pushNamed(context, AppRoutes.locationPickerRoute, arguments: data);
                                  setState(() {});
                                },
                                child: const Text('Pick location'),
                              ),
                            ),
                          ],
                        ),
                    ]
                  )
                )
              : ElevatedButton(
                onPressed: () => {loginUsingMetamask(context)},
                child: const Text("Connect with Metamask")
              ),
            ],
          )
        )
      )
    );
  }

  Future<void> updatePosition() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('location disabled');
      return Future.error('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
    }

    data.currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    print(data.currentPosition);
  }

  Future<bool> connectToWallet() async {
    print('connect to wallet');
    sessionStorage = WalletConnectSecureStorage();

    var __session = await sessionStorage.getSession();
    var uri = await storage.read(key: 'wc-uri');

    setState(() {
      _session = __session;
      data.connectionUri = uri;
    });

    data.connector =  WalletConnect(
      bridge: 'https://bridge.walletconnect.org',
      session: _session,
      sessionStorage: sessionStorage,
      clientMeta: const PeerMeta(
        name: 'Objective',
        description: 'Camera for Objective reporters.',
        url: 'https://walletconnect.org',
        icons: [
          'https://files.gitbook.com/v0/b/gitbook-legacy-files/o/spaces%2F-LJJeCjcLrr53DcT1Ml7%2Favatar.png?alt=media'
        ])
    );

    data.connector!.on(
        'connect',
        (session) => setState(
              () {
                _session = session;
              },
            ));
    data.connector!.on(
        'session_update',
        (payload) => setState(() {
              _session = payload;
              print(payload);
            }));
    data.connector!.on(
        'disconnect',
        (payload) => setState(() {
              _session = null;
            }));

    return true;
  }

  getNetworkName(chainId) {
    switch (chainId) {
      case 1:
        return 'Ethereum Mainnet';
      case 3:
        return 'Ropsten Testnet';
      case 4:
        return 'Rinkeby Testnet';
      case 5:
        return 'Goerli Testnet';
      case 42:
        return 'Kovan Testnet';
      case 137:
        return 'Polygon Mainnet';
      case 80001:
        return 'Mumbai Testnet';
      default:
        return 'Unknown Chain';
    }
  }
}
